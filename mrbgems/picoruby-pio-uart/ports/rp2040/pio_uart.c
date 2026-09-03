/*
 * A UART built out of PIO, with the receive side filled by DMA.
 *
 * The reason for the DMA is the reason this gem exists. A PIO state machine
 * has a four word FIFO, eight if it is given the one it does not use, and
 * nothing behind it: whatever arrives while it is full is gone, silently,
 * with no overrun flag to find it by. Polling that from Ruby means betting
 * that no garbage collection, no I2C write and no other task ever delays the
 * next look by more than eight byte times. At 115200 that is 700us. It is not
 * a bet worth making, and a game that sends its state every frame loses it.
 *
 * So the receive path never touches the processor. The state machine hands
 * each byte to DMA, DMA writes it into a ring in RAM whose address wraps in
 * hardware, and a second DMA channel chained to the first keeps writing the
 * transfer count back so it never finishes. Ruby reads out of a 512 byte
 * buffer at whatever pace it likes, and the only thing that can go wrong --
 * falling more than a whole buffer behind -- is detected and reported.
 *
 * The idiom is the usual one for this chip; dgatf/Pio-UART-RX-RP2040 is a
 * clear worked example of it.
 *
 * Transmit is a plain blocking write into the transmit FIFO. Nothing is lost
 * there because we control the pace, and 57 bytes at 115200 is 5ms.
 */

#include <string.h>

#include "hardware/clocks.h"
#include "hardware/dma.h"
#include "hardware/gpio.h"
#include "hardware/pio.h"

#include "../../include/pio_uart.h"

/* Eight state machine cycles a bit, so the clock is the baud rate times eight.
 *
 * The instruction words are pico-sdk's uart_tx.pio and uart_rx.pio, and they
 * are also exactly what picoruby-pio's assembler produces for the same
 * programs -- which is how they were verified before being frozen here.
 *
 *   tx: pull  side 1 [7] / set x,7 side 0 [7] / out pins,1 / jmp x-- 2 [6]
 *   rx: wait 0 pin 0     / set x,7       [10] / in  pins,1 / jmp x-- 2 [6]
 */
#define CYCLES_PER_BIT 8

static const uint16_t tx_instructions[] = {
  0x9fa0, 0xf727, 0x6001, 0x0642
};
static const uint16_t rx_instructions[] = {
  0x2020, 0xea27, 0x4001, 0x0642
};

static const struct pio_program tx_program = {
  .instructions = tx_instructions, .length = 4, .origin = -1
};
static const struct pio_program rx_program = {
  .instructions = rx_instructions, .length = 4, .origin = -1
};

/* A power of two, and the buffer has to be aligned to its own size: that is
 * what lets the DMA wrap the write address in hardware. */
#define RX_BITS 9
#define RX_SIZE (1u << RX_BITS)

static uint8_t rx_buffer[RX_SIZE] __attribute__((aligned(RX_SIZE)));

/* The count the reload channel writes back. Lives in RAM because DMA reads it.
 *
 * Not 0xffffffff. On RP2350 the top four bits of TRANS_COUNT are a MODE field
 * and 0xf means ENDLESS, which runs forever without decrementing the count --
 * so the channel happily fills the buffer while the count says nothing has
 * arrived. That is the whole register on RP2040, which is why every RP2040
 * example writes 0xffffffff and why this looked like a receive that was not
 * happening. 0x0fffffff is MODE=NORMAL with the largest count there is: six
 * and a half hours at this line rate before the reload comes round. */
#define RX_COUNT_MAX 0x0fffffffu
static const uint32_t rx_reload = RX_COUNT_MAX;

static struct {
  bool open;
  PIO pio;
  uint tx_sm, rx_sm;
  uint tx_offset, rx_offset;
  uint tx_pin, rx_pin;
  int rx_chan, rx_reload_chan;
  uint32_t read_pos;
  bool overflowed;
} link;

/* How many bytes DMA has written since the last reload. */
static inline uint32_t
rx_written(void)
{
  uint32_t remaining = dma_hw->ch[link.rx_chan].transfer_count & RX_COUNT_MAX;
  return RX_COUNT_MAX - remaining;
}

/* Notice, once, that the ring lapped us. */
static void
rx_check_overflow(uint32_t written)
{
  if ((written - link.read_pos) > RX_SIZE) {
    link.overflowed = true;
    link.read_pos = written - RX_SIZE;
  }
}

static void
setup_tx(uint32_t baudrate)
{
  pio_sm_config c = pio_get_default_sm_config();
  sm_config_set_wrap(&c, link.tx_offset, link.tx_offset + 3);
  sm_config_set_sideset(&c, 2, true, false);   /* one bit, optional */
  sm_config_set_sideset_pins(&c, link.tx_pin);
  sm_config_set_out_pins(&c, link.tx_pin, 1);
  sm_config_set_out_shift(&c, true, false, 32);
  sm_config_set_fifo_join(&c, PIO_FIFO_JOIN_TX);
  sm_config_set_clkdiv(&c, (float)clock_get_hz(clk_sys) /
                           (float)(baudrate * CYCLES_PER_BIT));

  /* High before the machine runs. The pin is an output the moment its
   * direction is set, and an output sitting at zero is a break. */
  pio_sm_set_pins_with_mask(link.pio, link.tx_sm, 1u << link.tx_pin,
                            1u << link.tx_pin);
  pio_sm_set_pindirs_with_mask(link.pio, link.tx_sm, 1u << link.tx_pin,
                               1u << link.tx_pin);
  pio_gpio_init(link.pio, link.tx_pin);
  pio_sm_init(link.pio, link.tx_sm, link.tx_offset, &c);
  pio_sm_set_enabled(link.pio, link.tx_sm, true);
}

static void
setup_rx(uint32_t baudrate)
{
  pio_sm_config c = pio_get_default_sm_config();
  sm_config_set_wrap(&c, link.rx_offset, link.rx_offset + 3);
  sm_config_set_in_pins(&c, link.rx_pin);
  sm_config_set_jmp_pin(&c, link.rx_pin);
  /* Shift right, autopush after eight bits: the byte lands in the top of the
   * FIFO word, which is the byte DMA is pointed at below. */
  sm_config_set_in_shift(&c, true, true, 8);
  sm_config_set_fifo_join(&c, PIO_FIFO_JOIN_RX);
  sm_config_set_clkdiv(&c, (float)clock_get_hz(clk_sys) /
                           (float)(baudrate * CYCLES_PER_BIT));

  /* Deliberately not forcing the pin to an input. PIO pin directions are
   * shared between the state machines on a block, so doing that would take
   * the transmit pin's output away when both name the same pin -- which is
   * exactly the wire-free loopback this gets tested on. A pin left alone is an
   * input anyway. */
  pio_gpio_init(link.pio, link.rx_pin);
  gpio_pull_up(link.rx_pin);   /* the line idles high, and nothing else holds it */
  pio_sm_init(link.pio, link.rx_sm, link.rx_offset, &c);
  pio_sm_set_enabled(link.pio, link.rx_sm, true);
}

static void
setup_rx_dma(void)
{
  /* The reload channel exists only to write the transfer count back, which is
   * what stops the data channel from ever finishing. */
  dma_channel_config r = dma_channel_get_default_config(link.rx_reload_chan);
  channel_config_set_transfer_data_size(&r, DMA_SIZE_32);
  channel_config_set_read_increment(&r, false);
  channel_config_set_write_increment(&r, false);
  dma_channel_configure(link.rx_reload_chan, &r,
                        &dma_hw->ch[link.rx_chan].al1_transfer_count_trig,
                        &rx_reload, 1, false);

  dma_channel_config d = dma_channel_get_default_config(link.rx_chan);
  channel_config_set_transfer_data_size(&d, DMA_SIZE_8);
  channel_config_set_read_increment(&d, false);
  channel_config_set_write_increment(&d, true);
  channel_config_set_ring(&d, true, RX_BITS);   /* wrap the write address */
  channel_config_set_dreq(&d, pio_get_dreq(link.pio, link.rx_sm, false));
  channel_config_set_chain_to(&d, link.rx_reload_chan);
  dma_channel_configure(link.rx_chan, &d,
                        rx_buffer,
                        /* the byte the autopush left at the top of the word */
                        (const uint8_t *)&link.pio->rxf[link.rx_sm] + 3,
                        RX_COUNT_MAX, false);
  dma_channel_start(link.rx_chan);
}

int
PIO_UART_open(uint8_t tx_pin, uint8_t rx_pin, uint32_t baudrate)
{
  if (link.open) return PIO_UART_E_BUSY;

  memset(&link, 0, sizeof(link));
  link.tx_pin = tx_pin;
  link.rx_pin = rx_pin;

  PIO pio = pio0;
  int tx_sm = pio_claim_unused_sm(pio, false);
  int rx_sm = pio_claim_unused_sm(pio, false);
  if (tx_sm < 0 || rx_sm < 0 ||
      !pio_can_add_program(pio, &tx_program) ||
      !pio_can_add_program(pio, &rx_program)) {
    if (0 <= tx_sm) pio_sm_unclaim(pio, tx_sm);
    if (0 <= rx_sm) pio_sm_unclaim(pio, rx_sm);
    pio = pio1;
    tx_sm = pio_claim_unused_sm(pio, false);
    rx_sm = pio_claim_unused_sm(pio, false);
    if (tx_sm < 0 || rx_sm < 0 ||
        !pio_can_add_program(pio, &tx_program) ||
        !pio_can_add_program(pio, &rx_program)) {
      if (0 <= tx_sm) pio_sm_unclaim(pio, tx_sm);
      if (0 <= rx_sm) pio_sm_unclaim(pio, rx_sm);
      return PIO_UART_E_NO_SM;
    }
  }
  link.pio = pio;
  link.tx_sm = (uint)tx_sm;
  link.rx_sm = (uint)rx_sm;

  link.rx_chan = dma_claim_unused_channel(false);
  link.rx_reload_chan = dma_claim_unused_channel(false);
  if (link.rx_chan < 0 || link.rx_reload_chan < 0) {
    if (0 <= link.rx_chan) dma_channel_unclaim(link.rx_chan);
    if (0 <= link.rx_reload_chan) dma_channel_unclaim(link.rx_reload_chan);
    pio_sm_unclaim(pio, link.tx_sm);
    pio_sm_unclaim(pio, link.rx_sm);
    return PIO_UART_E_NO_DMA;
  }

  link.tx_offset = pio_add_program(pio, &tx_program);
  link.rx_offset = pio_add_program(pio, &rx_program);

  setup_tx(baudrate);
  setup_rx(baudrate);
  setup_rx_dma();

  link.read_pos = rx_written();
  link.overflowed = false;
  link.open = true;
  return PIO_UART_OK;
}

void
PIO_UART_close(void)
{
  if (!link.open) return;
  dma_channel_abort(link.rx_chan);
  dma_channel_unclaim(link.rx_chan);
  dma_channel_unclaim(link.rx_reload_chan);
  pio_sm_set_enabled(link.pio, link.tx_sm, false);
  pio_sm_set_enabled(link.pio, link.rx_sm, false);
  pio_remove_program(link.pio, &tx_program, link.tx_offset);
  pio_remove_program(link.pio, &rx_program, link.rx_offset);
  pio_sm_unclaim(link.pio, link.tx_sm);
  pio_sm_unclaim(link.pio, link.rx_sm);
  link.open = false;
}

bool
PIO_UART_is_open(void)
{
  return link.open;
}

size_t
PIO_UART_write(const uint8_t *data, size_t len)
{
  if (!link.open) return 0;
  for (size_t i = 0; i < len; i++) {
    pio_sm_put_blocking(link.pio, link.tx_sm, (uint32_t)data[i]);
  }
  return len;
}

size_t
PIO_UART_available(void)
{
  if (!link.open) return 0;
  uint32_t written = rx_written();
  rx_check_overflow(written);
  return (size_t)(written - link.read_pos);
}

size_t
PIO_UART_read(uint8_t *out, size_t max)
{
  if (!link.open) return 0;
  uint32_t written = rx_written();
  rx_check_overflow(written);
  size_t n = (size_t)(written - link.read_pos);
  if (max < n) n = max;
  for (size_t i = 0; i < n; i++) {
    out[i] = rx_buffer[(link.read_pos + i) & (RX_SIZE - 1)];
  }
  link.read_pos += n;
  return n;
}

void
PIO_UART_clear(void)
{
  if (!link.open) return;
  link.read_pos = rx_written();
  link.overflowed = false;
}

bool
PIO_UART_take_overflow(void)
{
  if (!link.open) return false;
  rx_check_overflow(rx_written());
  bool was = link.overflowed;
  link.overflowed = false;
  return was;
}

size_t
PIO_UART_buffer_size(void)
{
  return RX_SIZE;
}
