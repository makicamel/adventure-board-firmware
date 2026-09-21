/*
 * picoruby-psg/ports/pico/psg_port.c
 */

#include "pico/stdlib.h"
#include "pico/time.h"
#include "pico/multicore.h"
#include "hardware/sync.h"
#include "hardware/irq.h"

#include <string.h>
#include <stdlib.h>

#include "../../include/psg.h"

// Critical section
#if defined(PICO_RP2040) || defined(PICO_RP2350)

static spin_lock_t *psg_spin;

/**
 * __attribute__((constructor)): Will be called before main() is executed.
 */
__attribute__((constructor))
static void
psg_port_init(void)
{
  /* The packet ring buffer and PSG state are shared by core0 and core1. */
  psg_spin = spin_lock_instance(spin_lock_claim_unused(true));
}

PSG_HOT psg_cs_token_t
PSG_enter_critical(void)
{
  return spin_lock_blocking(psg_spin);
}

PSG_HOT void
PSG_exit_critical(psg_cs_token_t token)
{
  spin_unlock(psg_spin, token);
}

#endif

#define ALARM_AUDIO 1
#define ALARM_TICK  2

// Tick timer

static volatile uint32_t g_tick_ms = 0;
static repeating_timer_t tick_timer;

PSG_HOT static inline void
psg_process_packets(void)
{
  psg_packet_t pkt;
  while (PSG_rb_peek(&pkt)) {
    if (0 < (int32_t)(pkt.tick - g_tick_ms)) return;
    g_tick_ms -= pkt.tick;
    PSG_rb_pop();
    PSG_process_packet(&pkt);
  }
  g_tick_ms = 0;
}

PSG_HOT static bool
tick_cb(repeating_timer_t *t)
{
  (void)t;
  g_tick_ms++;
  psg_process_packets();
  PSG_tick_1ms();   /* update internal LFO etc. */
//  if (psg_drv == &psg_drv_usbaudio) {
//    audio_task();
//  }
  return true;
}

static alarm_pool_t *audio_alarm_pool = NULL;
static alarm_pool_t *tick_alarm_pool = NULL;

static volatile bool core1_alive = false;

// Audio timer (must be declared before psg_core1_main)
static repeating_timer_t audio_timer;

#ifndef PSG_DEBUG_AUDIO_PIN
#define PSG_DEBUG_AUDIO_PIN -1
#endif

#if PSG_DEBUG_AUDIO_PIN >= 0
#define DBG_TOGGLE()  (sio_hw->gpio_togl = 1u << PSG_DEBUG_AUDIO_PIN)

static inline void
debug_audio_pin_init(void)
{
  gpio_init(PSG_DEBUG_AUDIO_PIN);
  gpio_set_dir(PSG_DEBUG_AUDIO_PIN, GPIO_OUT);
  gpio_put(PSG_DEBUG_AUDIO_PIN, 0);
}
#else
#define DBG_TOGGLE()  ((void)0)

static inline void
debug_audio_pin_init(void)
{
}
#endif

static bool
audio_cb(repeating_timer_t *t)
{
  (void)t;
  DBG_TOGGLE();
  PSG_audio_cb();
  DBG_TOGGLE();
  return true;
}

enum {
  ACK_CORE1_READY = 0xA5,
  ACK_DONE,
};

/* core0 asks core1 to clean up through this flag, not through the
 * inter-core FIFO: once core1 is a lockout victim (see psg_core1_main)
 * the SDK's FIFO interrupt handler owns core1's receive side and drops
 * every word that is not a lockout request. core1's replies still go
 * through the FIFO, which is the other direction. */
static volatile bool core1_cleanup_requested = false;

#if defined(PICO_RP2350)
#define PICORB_IRQ_1 TIMER1_IRQ_1
#define PICORB_IRQ_2 TIMER1_IRQ_2
#elif defined(PICO_RP2040)
#define PICORB_IRQ_1 TIMER_IRQ_1
#define PICORB_IRQ_2 TIMER_IRQ_2
#endif

static void __attribute__((noreturn))
psg_core1_cleanup(void)
{
  if (audio_alarm_pool) {
    cancel_repeating_timer(&audio_timer);
    alarm_pool_destroy(audio_alarm_pool);
    audio_alarm_pool = NULL;
  }
  if (tick_alarm_pool) {
    cancel_repeating_timer(&tick_timer);
    alarm_pool_destroy(tick_alarm_pool);
    tick_alarm_pool = NULL;
  }
  if (psg_drv) {
    psg_drv->stop();
    psg_drv = NULL;
  }
  multicore_fifo_push_blocking(ACK_DONE);
  for (;;) tight_loop_contents();
}

PSG_HOT static inline void
psg_core1_poll_command(void)
{
  if (core1_cleanup_requested) psg_core1_cleanup();
}

PSG_HOT static void __attribute__((noreturn))
psg_core1_main(void)
{
  uint8_t p1 = (uint8_t)multicore_fifo_pop_blocking();
  uint8_t p2 = (uint8_t)multicore_fifo_pop_blocking();
  /* This core never pauses, and although the block loop is in RAM, the
   * SDK's timer interrupt path is in flash. So whoever erases or programs
   * flash on core0 has to be able to park it first -- otherwise it faults
   * on its next instruction fetch and locks up. After the two
   * pops above, because from here on the FIFO interrupt takes what
   * core0 sends. */
  multicore_lockout_victim_init();
  psg_drv->init(p1, p2); /* init PSG driver */
  psg_drv->start();
  bool use_buffer_output = psg_drv->write_buffer != NULL;

  if (!tick_alarm_pool) {
    tick_alarm_pool = alarm_pool_create(ALARM_TICK, 2);
    assert(tick_alarm_pool && "Failed to create alarm tick_alarm_pool");
    irq_set_priority(PICORB_IRQ_2, 3);
  }
  memset(&tick_timer, 0, sizeof(repeating_timer_t));
  /* 1 kHz = -1000 µs */
  if (!alarm_pool_add_repeating_timer_us(tick_alarm_pool, -1000, tick_cb, NULL, &tick_timer)) {
    assert(false && "Failed to add repeating timer");
  }

  if (!use_buffer_output) {
    if (!audio_alarm_pool) {
      audio_alarm_pool = alarm_pool_create(ALARM_AUDIO, 2);
      assert(audio_alarm_pool && "Failed to create alarm audio_alarm_pool");
      irq_set_priority(PICORB_IRQ_1, 0);
    }
    memset(&audio_timer, 0, sizeof(repeating_timer_t));
    /* 22.05 kHz */
    if (!alarm_pool_add_repeating_timer_us(audio_alarm_pool, -1000000 / SAMPLE_RATE, audio_cb, NULL, &audio_timer)) {
      assert(false && "Failed to add repeating timer");
    }
  }

  multicore_fifo_push_blocking(ACK_CORE1_READY);

  uint32_t buffer_output_pos = 0;

  for (;;) {
    if (use_buffer_output) {
      uint32_t *dst = &pcm_buf[buffer_output_pos];
      PSG_render_block(dst, PSG_BUFFER_OUTPUT_SAMPLES);
      while (!psg_drv->write_buffer(dst, PSG_BUFFER_OUTPUT_SAMPLES)) {
        tight_loop_contents();
        psg_core1_poll_command();
      }
      buffer_output_pos = (buffer_output_pos + PSG_BUFFER_OUTPUT_SAMPLES) & BUF_MASK;
    } else {
      // core1 is responsible for rendering audio samples (heavy load)
      uint32_t used = wr_idx - rd_idx;
      if (used <= BUF_SAMPLES / 2) {
        uint32_t dst_pos = wr_idx & BUF_MASK;  // Start position to write
        // How many words can we write at the end of the buffer?
        uint32_t first_len = MIN(BUF_SAMPLES - dst_pos, BUF_SAMPLES / 2);
        PSG_render_block(&pcm_buf[dst_pos], first_len);
        // If there are remaining words, write them at the beginning of the buffer
        if (first_len < BUF_SAMPLES / 2) {
          PSG_render_block(pcm_buf, BUF_SAMPLES / 2 - first_len);
        }
        wr_idx += BUF_SAMPLES / 2;
      }
    }

    tight_loop_contents();
    psg_core1_poll_command();
  }

}


void
PSG_tick_start_core1(uint8_t p1, uint8_t p2)
{
  debug_audio_pin_init();
  g_tick_ms = 0;

  if (psg_drv && psg_drv->write_buffer) {
    rd_idx = 0;
    wr_idx = 0;
  } else {
    PSG_render_block(pcm_buf, BUF_SAMPLES);
    rd_idx = 0;
    wr_idx = BUF_SAMPLES;
  }

  if (!core1_alive) {
    multicore_launch_core1(psg_core1_main);
    // send pin via FIFO
    multicore_fifo_push_blocking(p1);
    multicore_fifo_push_blocking(p2);
    uint32_t ack = multicore_fifo_pop_blocking();
    if (ack != ACK_CORE1_READY) {
      //printf("Unexpected core1 ready ack: 0x%08x\n", ack);
    }
    core1_alive = true;
  }

}

void
PSG_tick_stop_core1(void)
{
  if (core1_alive) {
    core1_cleanup_requested = true;
    while (multicore_fifo_pop_blocking() != ACK_DONE) {
      // wait
    }
    multicore_reset_core1();
    core1_cleanup_requested = false;
    core1_alive = false;
  } else if (psg_drv) {
    psg_drv->stop();
    psg_drv = NULL;
  }
}
