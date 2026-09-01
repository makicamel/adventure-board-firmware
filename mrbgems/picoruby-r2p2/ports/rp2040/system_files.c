/*
 * Puts the board library and the sample programs on the filesystem.
 *
 * The firmware UF2 covers 0x10000000 upwards and stops well short of the
 * littlefs region at 0x10380000, so flashing never touches the filesystem and
 * cannot deliver files to it. Rather than ask for a second image or a transfer
 * over the wire, the files ride in the firmware and are written out here, on
 * the first boot that finds them missing — which is also the boot where
 * littlefs_ensure_mounted() formats a blank flash.
 *
 * This runs before the VM opens: core1 is not up and interrupts are not yet
 * being taken, which is the calmest moment for flash writes.
 */

#include <string.h>
#include <stdio.h>

#include "system_files.h"
#include "../../../picoruby-littlefs/include/littlefs.h"

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

static void
write_file(lfs_t *lfs, const picorb_system_file_t *entry)
{
  lfs_file_t file;
  int err = lfs_file_open(lfs, &file, entry->path,
                          LFS_O_WRONLY | LFS_O_CREAT | LFS_O_TRUNC);
  if (err != LFS_ERR_OK) {
    printf("[R2P2] open %s failed (%d)\n", entry->path, err);
    return;
  }
  lfs_ssize_t written = lfs_file_write(lfs, &file, entry->data,
                                       (lfs_size_t)entry->size);
  lfs_file_close(lfs, &file);
  if (written < 0 || (size_t)written != entry->size) {
    printf("[R2P2] write %s failed (%ld)\n", entry->path, (long)written);
  } else {
    printf("[R2P2] installed %s (%u bytes)\n", entry->path,
           (unsigned)entry->size);
  }
}

void
picorb_install_system_files(void)
{
  const picorb_system_file_t *entry = picorb_system_files;
  if (entry->path == NULL) return;

  /* Formats a blank flash and mounts it. Ruby mounts the same instance later. */
  int err = littlefs_ensure_mounted();
  if (err != LFS_ERR_OK) {
    printf("[R2P2] filesystem not available (%d); skipping system files\n", err);
    return;
  }
  lfs_t *lfs = littlefs_get_lfs();

  while (entry->path != NULL) {
    if (!file_exists(lfs, entry->path)) {
      ensure_parent_dirs(lfs, entry->path);
      write_file(lfs, entry);
    }
    entry++;
  }
}
