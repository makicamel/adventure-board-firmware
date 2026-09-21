#include <string.h>
#include <hardware/sync.h>
#include <hardware/flash.h>
#include <pico/multicore.h>

#include "../../lib/littlefs/lfs.h"
#include "../../include/littlefs.h"

#if !defined(LFS_FLASH_TARGET_OFFSET)
  #if defined(PICO_RP2040)
    #define LFS_FLASH_TARGET_OFFSET  0x00180000
  #elif defined(PICO_RP2350)
    #define LFS_FLASH_TARGET_OFFSET  0x00380000
  #endif
#endif

#define LFS_FLASH_MMAP_ADDR    (XIP_BASE + LFS_FLASH_TARGET_OFFSET)
#define LFS_FLASH_BLOCK_SIZE   4096  /* == FLASH_SECTOR_SIZE */
#define LFS_FLASH_BLOCK_COUNT  128   /* 512 KB */

/*
 * Flash cannot be read while it is being erased or programmed, and the
 * program itself runs from it. Masking interrupts keeps this core out of
 * flash, but not the other one: a core1 that is running (picoruby-psg
 * renders audio there) fetches its next instruction from a flash that is
 * not answering, faults, faults again in the handler, and locks up.
 * So core1 is parked first, in the SDK's RAM-resident lockout handler.
 * It can only be parked once it has called multicore_lockout_victim_init();
 * until then it is either not running or not ours to stop.
 */
typedef struct {
  bool locked;
  uint32_t ints;
} flash_guard_t;

static flash_guard_t
flash_guard_enter(void)
{
  flash_guard_t g;
  g.locked = (get_core_num() == 0) && multicore_lockout_victim_is_initialized(1);
  if (g.locked) multicore_lockout_start_blocking();
  g.ints = save_and_disable_interrupts();
  return g;
}

static void
flash_guard_exit(flash_guard_t g)
{
  restore_interrupts(g.ints);
  if (g.locked) multicore_lockout_end_blocking();
}

static int
lfs_flash_read(const struct lfs_config *c, lfs_block_t block,
               lfs_off_t off, void *buffer, lfs_size_t size)
{
  memcpy(buffer,
         (uint8_t *)(LFS_FLASH_MMAP_ADDR + block * c->block_size + off),
         size);
  return LFS_ERR_OK;
}

static int
lfs_flash_prog(const struct lfs_config *c, lfs_block_t block,
               lfs_off_t off, const void *buffer, lfs_size_t size)
{
  uint32_t addr = LFS_FLASH_TARGET_OFFSET + block * c->block_size + off;
  flash_guard_t g = flash_guard_enter();
  flash_range_program(addr, (const uint8_t *)buffer, size);
  flash_guard_exit(g);
  return LFS_ERR_OK;
}

static int
lfs_flash_erase(const struct lfs_config *c, lfs_block_t block)
{
  uint32_t addr = LFS_FLASH_TARGET_OFFSET + block * c->block_size;
  flash_guard_t g = flash_guard_enter();
  flash_range_erase(addr, c->block_size);
  flash_guard_exit(g);
  return LFS_ERR_OK;
}

static int
lfs_flash_sync(const struct lfs_config *c)
{
  (void)c;
  return LFS_ERR_OK;
}

void
littlefs_hal_init_config(struct lfs_config *cfg)
{
  memset(cfg, 0, sizeof(struct lfs_config));
  cfg->read  = lfs_flash_read;
  cfg->prog  = lfs_flash_prog;
  cfg->erase = lfs_flash_erase;
  cfg->sync  = lfs_flash_sync;

  cfg->read_size      = FLASH_PAGE_SIZE;   /* 256 */
  cfg->prog_size      = FLASH_PAGE_SIZE;   /* 256 */
  cfg->block_size     = LFS_FLASH_BLOCK_SIZE;
  cfg->block_count    = LFS_FLASH_BLOCK_COUNT;
  cfg->block_cycles   = 500;
  cfg->cache_size     = FLASH_PAGE_SIZE;   /* 256 */
  cfg->lookahead_size = 16;
}

void
littlefs_hal_erase_all(void)
{
  flash_guard_t g = flash_guard_enter();
  flash_range_erase(
    (uint32_t)LFS_FLASH_TARGET_OFFSET,
    (size_t)(LFS_FLASH_BLOCK_SIZE * LFS_FLASH_BLOCK_COUNT)
  );
  flash_guard_exit(g);
}
