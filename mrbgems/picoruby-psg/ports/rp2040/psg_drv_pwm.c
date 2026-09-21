#include "pico/stdlib.h"
#include "hardware/pwm.h"

#ifndef PSG_PWM_DMA
#define PSG_PWM_DMA 0
#endif

#if PSG_PWM_DMA
#include "hardware/clocks.h"
#include "hardware/dma.h"
#endif

#include "../../include/psg.h"

#define PWM_STOP_SETTLE_US 50

static uint slice_num;
static bool pwm_initialized = false;
static bool left_is_a = true;

#if PSG_PWM_DMA
/*
 * One PWM period per sample puts the carrier at the sample rate, 22 kHz:
 * right on top of the audio band, where no reasonable output filter can
 * take it out (an RC pair sized for a >100 kHz carrier passes it almost
 * untouched), and with a fractional clock divider that the SDK truncates
 * to 8.4 bits, so the rate actually played was 22536 Hz, 38 cents sharp.
 *
 * Instead the slice runs undivided and every sample is written for
 * PSG_PWM_OVERSAMPLE consecutive periods: TOP = clk_sys / (rate * 6) - 1,
 * which is 1132 at 150 MHz -- a 132 kHz carrier and 22065 Hz -- and 943
 * at 125 MHz. TOP + 1 levels are fewer than the 4096 a sample has, so
 * the remainder is spread over the six periods (each gets the quotient,
 * the first few one more), which keeps the average exact to 1/6 level.
 */
#define PSG_PWM_OVERSAMPLE 6

/*
 * Two DMA channels that chain to each other, one buffer each. While one
 * plays, the next block is expanded into the other's buffer and that
 * channel is loaded without a trigger; the hardware starts it on the very
 * PWM period after the first one ends. Re-arming a single channel from
 * software lost two periods at every block boundary: 0.5% flat, and a
 * phase step 344 times a second.
 * The third buffer holds the mid-scale level. A channel that gets chained
 * to before it was reloaded (core1 was late) reads on past its own buffer:
 * channel 0 repeats channel 1's block, channel 1 plays the third buffer.
 * Mid-scale is where the output rests, so that is a gap, not a bang (it
 * was zero at first: a full-scale step down and back, 2.9 ms long).
 * Only the first miss is covered. A core1 that stays away for several
 * blocks -- parked while core0 writes flash -- lets the read addresses run
 * on into whatever follows.
 */
static int dma_chan[2] = { -1, -1 };
static uint32_t dma_buf[3][PSG_BUFFER_OUTPUT_SAMPLES * PSG_PWM_OVERSAMPLE];
static uint8_t dma_playing = 0;           /* the channel that is (or was last) running */
static bool dma_started = false;
static bool dma_queued = false;           /* the other channel is loaded and waiting */
static uint32_t pwm_levels;   /* TOP + 1 */

static inline void psg_pwm_pack_sample(uint32_t sample, uint32_t *dst);
#endif

static void
psg_pwm_shutdown(void)
{
  if (!pwm_initialized) return;

#if PSG_PWM_DMA
  for (int i = 0; i < 2; i++) {
    if (dma_chan[i] < 0) continue;
    /* break the chain first, or aborting one starts the other */
    hw_write_masked(&dma_hw->ch[dma_chan[i]].al1_ctrl,
                    (uint32_t)dma_chan[i] << DMA_CH0_CTRL_TRIG_CHAIN_TO_LSB,
                    DMA_CH0_CTRL_TRIG_CHAIN_TO_BITS);
  }
  for (int i = 0; i < 2; i++) {
    if (dma_chan[i] < 0) continue;
    dma_channel_abort(dma_chan[i]);
    dma_channel_cleanup(dma_chan[i]);
    dma_channel_unclaim(dma_chan[i]);
    dma_chan[i] = -1;
  }
  dma_started = false;
  dma_queued = false;
#endif

  pwm_set_both_levels(slice_num, 0, 0);
  sleep_us(PWM_STOP_SETTLE_US);
  pwm_set_enabled(slice_num, false);
  pwm_initialized = false;
}

static void
psg_pwm_init(uint8_t lpin, uint8_t rpin)
{
  uint l_gpio = (uint)lpin;
  uint r_gpio = (uint)rpin;
  uint l_slice = pwm_gpio_to_slice_num(l_gpio);
  uint r_slice = pwm_gpio_to_slice_num(r_gpio);

  psg_pwm_shutdown();

  if (l_slice != r_slice) {
    // ToDo: Should raise an exception
    return;
  }

  gpio_set_function(l_gpio, GPIO_FUNC_PWM);
  gpio_set_function(r_gpio, GPIO_FUNC_PWM);

  slice_num = l_slice;
  left_is_a = (pwm_gpio_to_channel(l_gpio) == PWM_CHAN_A);

  /* common settings ------------------------------------------------ */
#if PSG_PWM_DMA
  pwm_levels = clock_get_hz(clk_sys) / (SAMPLE_RATE * PSG_PWM_OVERSAMPLE);
  pwm_set_wrap(slice_num, (uint16_t)(pwm_levels - 1));
  pwm_set_clkdiv_int_frac(slice_num, 1, 0);
#else
  pwm_set_wrap(slice_num, MAX_SAMPLE_WIDTH);
  /* optional: div = 1.0 (125 MHz) -> 30.5 kHz carrier @ wrap 4095   */
  pwm_set_clkdiv_int_frac(slice_num, 1, 0);
#endif

  /* start with zero level to avoid pop                               */
  pwm_set_both_levels(slice_num, 0, 0);

#if PSG_PWM_DMA
  dma_chan[0] = dma_claim_unused_channel(true);
  dma_chan[1] = dma_claim_unused_channel(true);
  for (int i = 0; i < 2; i++) {
    dma_channel_config c = dma_channel_get_default_config(dma_chan[i]);
    channel_config_set_transfer_data_size(&c, DMA_SIZE_32);
    channel_config_set_read_increment(&c, true);
    channel_config_set_write_increment(&c, false);
    channel_config_set_dreq(&c, pwm_get_dreq(slice_num));
    channel_config_set_chain_to(&c, dma_chan[i ^ 1]);
    dma_channel_configure(dma_chan[i], &c, &pwm_hw->slice[slice_num].cc, dma_buf[i], 0, false);
  }
  for (uint32_t i = 0; i < PSG_BUFFER_OUTPUT_SAMPLES; i++) {
    uint32_t mid = (MAX_SAMPLE_WIDTH + 1) / 2;
    psg_pwm_pack_sample((mid << 16) | mid, &dma_buf[2][i * PSG_PWM_OVERSAMPLE]);
  }
  dma_playing = 0;
  dma_started = false;
  dma_queued = false;
#endif

  pwm_set_enabled(slice_num, true);
  pwm_initialized = true;
}

static void
psg_pwm_start(void)
{
  if (pwm_initialized) pwm_set_enabled(slice_num, true);
}

static void
psg_pwm_stop(void)
{
  psg_pwm_shutdown();
}

static void
psg_pwm_write(uint16_t l, uint16_t r)
{
  if (!pwm_initialized) return;

  if (left_is_a) {
    pwm_set_both_levels(slice_num, l, r);
  } else {
    pwm_set_both_levels(slice_num, r, l);
  }
}

#if PSG_PWM_DMA
/* The SDK's DMA accessors are plain `static inline`: in a debug build they
 * stay out of line (and in flash), so the block path touches the registers
 * itself. */
#define DMA_BUSY(n)   ((dma_hw->ch[n].ctrl_trig & DMA_CH0_CTRL_TRIG_BUSY_BITS) != 0)

/* The CC words for the PSG_PWM_OVERSAMPLE periods one sample lasts. */
PSG_HOT static inline void
psg_pwm_pack_sample(uint32_t sample, uint32_t *dst)
{
  /* 0..4095 -> 0..pwm_levels, in sixths of a level */
  uint32_t l6 = ((sample >> 16) & MAX_SAMPLE_WIDTH) * pwm_levels * PSG_PWM_OVERSAMPLE >> PWM_BITS;
  uint32_t r6 = (sample & MAX_SAMPLE_WIDTH) * pwm_levels * PSG_PWM_OVERSAMPLE >> PWM_BITS;
  uint32_t lq = l6 / PSG_PWM_OVERSAMPLE, lr = l6 % PSG_PWM_OVERSAMPLE;
  uint32_t rq = r6 / PSG_PWM_OVERSAMPLE, rr = r6 % PSG_PWM_OVERSAMPLE;
  for (uint32_t k = 0; k < PSG_PWM_OVERSAMPLE; k++) {
    uint32_t l = lq + (k < lr);
    uint32_t r = rq + (k < rr);
    dst[k] = left_is_a ? ((r << 16) | l) : ((l << 16) | r);
  }
}

PSG_HOT static bool
psg_pwm_write_buffer(const uint32_t *samples, uint32_t count)
{
  if (!pwm_initialized || dma_chan[0] < 0 || count > PSG_BUFFER_OUTPUT_SAMPLES) return false;

  /* The caller retries with the same block until it is accepted. */
  if (dma_queued) {
    /* Both buffers are taken until the running channel ends and the
     * hardware moves on to the queued one. */
    if (DMA_BUSY(dma_chan[dma_playing])) return false;
    dma_playing ^= 1;
    dma_queued = false;
  }
  uint8_t target = dma_started ? (dma_playing ^ 1) : dma_playing;
  for (uint32_t i = 0; i < count; i++) {
    psg_pwm_pack_sample(samples[i], &dma_buf[target][i * PSG_PWM_OVERSAMPLE]);
  }
  dma_hw->ch[dma_chan[target]].read_addr = (uintptr_t)dma_buf[target];
  if (dma_started) {
    dma_hw->ch[dma_chan[target]].transfer_count = count * PSG_PWM_OVERSAMPLE;
    dma_queued = true;
  } else {
    dma_hw->ch[dma_chan[target]].al1_transfer_count_trig = count * PSG_PWM_OVERSAMPLE;
    dma_started = true;
  }
  return true;
}
#endif

const psg_output_api_t psg_drv_pwm = {
  .init         = psg_pwm_init,
  .start        = psg_pwm_start,
  .stop         = psg_pwm_stop,
  .write        = psg_pwm_write,
#if PSG_PWM_DMA
  .write_buffer = psg_pwm_write_buffer
#else
  .write_buffer = NULL
#endif
};
