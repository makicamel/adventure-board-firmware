#include "pico/stdlib.h"
#include "hardware/adc.h"
#include "hardware/dma.h"

#include "../../include/adc_capture.h"

/* The DMA ring wraps the low ADC_CAPTURE_RING_BITS of the write address, so
 * the buffer has to start on a multiple of its own size. Anywhere else the
 * transfer wraps into whatever lies below the buffer -- which is how the
 * first version of this took out the SDK's spin locks. */
static uint8_t ring[ADC_CAPTURE_SIZE] __attribute__((aligned(ADC_CAPTURE_SIZE)));
static int dma_chan = -1;

bool
ADC_capture_start(uint8_t pin, uint32_t rate_hz)
{
  if (pin < 26 || 29 < pin || rate_hz == 0) return false;
  if (0 <= dma_chan) ADC_capture_stop();

  adc_init();
  adc_gpio_init(pin);
  adc_select_input(pin - 26);
  adc_fifo_setup(true,   /* write each conversion to the FIFO */
                 true,   /* raise DREQ */
                 1,
                 false,
                 true);  /* keep the upper 8 bits: one byte a sample */
  /* clk_adc is 48 MHz and one conversion is 96 cycles, so 500 kS/s flat out */
  adc_set_clkdiv(48000000.0f / (float)rate_hz - 1.0f);

  dma_chan = dma_claim_unused_channel(false);
  if (dma_chan < 0) return false;
  dma_channel_config c = dma_channel_get_default_config(dma_chan);
  channel_config_set_transfer_data_size(&c, DMA_SIZE_8);
  channel_config_set_read_increment(&c, false);
  channel_config_set_write_increment(&c, true);
  channel_config_set_ring(&c, true, ADC_CAPTURE_RING_BITS);   /* wrap the write address */
  channel_config_set_dreq(&c, DREQ_ADC);
  /* Not 0xffffffff: on the RP2350 the top four bits of TRANS_COUNT are MODE.
   * This many samples is days at any rate that fits the ring. */
  dma_channel_configure(dma_chan, &c, ring, &adc_hw->fifo, 0x0fffffff, true);
  adc_run(true);
  return true;
}

uint32_t
ADC_capture_stop(void)
{
  if (dma_chan < 0) return 0;
  adc_run(false);
  uint32_t next = (uint32_t)dma_hw->ch[dma_chan].write_addr - (uint32_t)ring;
  dma_channel_abort(dma_chan);
  dma_channel_cleanup(dma_chan);
  dma_channel_unclaim(dma_chan);
  dma_chan = -1;
  adc_fifo_drain();
  return next & (ADC_CAPTURE_SIZE - 1);
}

uint32_t
ADC_capture_addr(void)
{
  return (uint32_t)ring;
}
