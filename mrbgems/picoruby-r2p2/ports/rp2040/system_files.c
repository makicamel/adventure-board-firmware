/*
 * Puts the board library and the sample programs on the filesystem.
 *
 * The firmware UF2 covers 0x10000000 upwards and stops well short of the
 * littlefs region at 0x10380000, so flashing never touches the filesystem and
 * cannot deliver files to it. Rather than ask for a second image or a transfer
 * over the wire, the files ride in the firmware and are written out here, on
 * the first boot that finds them missing — which is also the boot where
 * littlefs_ensure_mounted() formats a blank flash — and again whenever the
 * firmware carries a different set than the board is holding.
 *
 * This runs before the VM opens: core1 is not up and interrupts are not yet
 * being taken, which is the calmest moment for flash writes. It is also before
 * USB, which means a board that hangs in here cannot be talked to at all --
 * only BOOTSEL gets it back. A filesystem damaged by a crash mid-write is
 * enough to do that: littlefs walks its directories as a linked list, and a
 * broken tail pointer is a cycle. So the whole thing runs under a watchdog and
 * gives up on itself if it ever comes back from one. Losing the samples is a
 * bad boot; losing the board is a dead board.
 */

#include <string.h>
#include <stdio.h>

#include "hardware/watchdog.h"

#include "system_files.h"
#include "../../../picoruby-littlefs/include/littlefs.h"

/* Left in scratch[0] while the filesystem is being touched, and cleared once
 * it is done. scratch[4..7] belong to watchdog_reboot(), so keep off those. */
#define INSTALL_IN_PROGRESS 0x5f5f4c49  /* "IL__" */
#define INSTALL_TIMEOUT_MS  8000

/* Beside R2P2's own /etc/ruby-description, which is the same idea for /bin. */
#define STAMP_PATH "/etc/adventure-board-files"
#define STAMP_MAX  32

/* Create every directory along the path, ignoring the ones already there. */
static void
ensure_parent_dirs(lfs_t *lfs, const char *path)
{
  char buf[LFS_NAME_MAX + 1];
  size_t len = strlen(path);
  if (len >= sizeof(buf)) return;
  memcpy(buf, path, len + 1);

  for (size_t i = 1; i < len; i++) {
    if (buf[i] != '/') continue;
    buf[i] = '\0';
    int err = lfs_mkdir(lfs, buf);
    if (err != LFS_ERR_OK && err != LFS_ERR_EXIST) {
      printf("[R2P2] mkdir %s failed (%d)\n", buf, err);
    }
    buf[i] = '/';
  }
}

static bool
file_exists(lfs_t *lfs, const char *path)
{
  struct lfs_info info;
  return lfs_stat(lfs, path, &info) == LFS_ERR_OK;
}

static bool
write_bytes(lfs_t *lfs, const char *path, const void *data, size_t size)
{
  lfs_file_t file;
  int err = lfs_file_open(lfs, &file, path,
                          LFS_O_WRONLY | LFS_O_CREAT | LFS_O_TRUNC);
  if (err != LFS_ERR_OK) {
    printf("[R2P2] open %s failed (%d)\n", path, err);
    return false;
  }
  lfs_ssize_t written = lfs_file_write(lfs, &file, data, (lfs_size_t)size);
  lfs_file_close(lfs, &file);
  if (written < 0 || (size_t)written != size) {
    printf("[R2P2] write %s failed (%ld)\n", path, (long)written);
    return false;
  }
  printf("[R2P2] installed %s (%u bytes)\n", path, (unsigned)size);
  return true;
}

/* True when the board already holds exactly what this firmware carries. */
/* The board library used to be /lib/picorubykaigi01; a board that had it
 * keeps it after the firmware moves on, since the installer only writes.
 * Taken away once, the first time a firmware with the new name runs (the
 * stamp does not match then). One level deep is all there was. */
static void
remove_old_library(lfs_t *lfs)
{
  static const char *old_dir = "/lib/picorubykaigi01";
  lfs_dir_t dir;
  if (lfs_dir_open(lfs, &dir, old_dir) == LFS_ERR_OK) {
    struct lfs_info info;
    char path[64];
    while (lfs_dir_read(lfs, &dir, &info) > 0) {
      if (info.type != LFS_TYPE_REG) continue;
      snprintf(path, sizeof(path), "%s/%s", old_dir, info.name);
      lfs_remove(lfs, path);
    }
    lfs_dir_close(lfs, &dir);
    if (lfs_remove(lfs, old_dir) == LFS_ERR_OK) {
      printf("[R2P2] removed %s\n", old_dir);
    }
  }
  lfs_remove(lfs, "/lib/picorubykaigi01.rb");
  lfs_remove(lfs, "/etc/picorubykaigi01-files");
}

static bool
stamp_matches(lfs_t *lfs)
{
  lfs_file_t file;
  char buf[STAMP_MAX];
  if (lfs_file_open(lfs, &file, STAMP_PATH, LFS_O_RDONLY) != LFS_ERR_OK) {
    return false;
  }
  lfs_ssize_t n = lfs_file_read(lfs, &file, buf, sizeof(buf) - 1);
  lfs_file_close(lfs, &file);
  if (n <= 0) return false;
  buf[n] = '\0';
  return strcmp(buf, picorb_system_files_stamp) == 0;
}

void
picorb_install_system_files(void)
{
  const picorb_system_file_t *entry = picorb_system_files;
  if (entry->path == NULL) return;

  /* Came back from a watchdog with the flag still set: the last attempt did
   * not finish. Do not try again -- boot to a shell instead, where the
   * filesystem can be looked at and reformatted. */
  if (watchdog_caused_reboot() &&
      watchdog_hw->scratch[0] == INSTALL_IN_PROGRESS) {
    watchdog_hw->scratch[0] = 0;
    printf("[R2P2] system file install hung last boot; skipping\n");
    return;
  }

  watchdog_hw->scratch[0] = INSTALL_IN_PROGRESS;
  watchdog_enable(INSTALL_TIMEOUT_MS, 0);

  /* Formats a blank flash and mounts it. Ruby mounts the same instance later. */
  int err = littlefs_ensure_mounted();
  if (err != LFS_ERR_OK) {
    printf("[R2P2] filesystem not available (%d); skipping system files\n", err);
  } else {
    lfs_t *lfs = littlefs_get_lfs();
    if (stamp_matches(lfs)) {
      /* Nothing has changed since the last boot that wrote these. */
      watchdog_disable();
      watchdog_hw->scratch[0] = 0;
      return;
    }
    remove_old_library(lfs);
    bool complete = true;
    while (entry->path != NULL) {
      if (entry->refresh || !file_exists(lfs, entry->path)) {
        ensure_parent_dirs(lfs, entry->path);
        if (!write_bytes(lfs, entry->path, entry->data, entry->size)) {
          complete = false;
        }
      }
      /* Formatting a blank flash erases 512KB and every miss writes a file, so
       * the budget is for the whole table rather than per entry. */
      watchdog_update();
      entry++;
    }
    /* Only claim the stamp if every file really landed; otherwise the next
     * boot has to try again rather than trust it. */
    if (complete) {
      ensure_parent_dirs(lfs, STAMP_PATH);
      write_bytes(lfs, STAMP_PATH, picorb_system_files_stamp,
                  strlen(picorb_system_files_stamp));
    } else {
      lfs_remove(lfs, STAMP_PATH);
    }
  }

  watchdog_disable();
  watchdog_hw->scratch[0] = 0;
}
