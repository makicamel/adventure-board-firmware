#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include "hardware/gpio.h"
#include "hardware/uart.h"
#include "pico/stdlib.h"
#include "hardware/irq.h"
#include "hardware/sync.h"
#include "hardware/timer.h"

#include "../../include/uart.h"

/*
 * The PIO unit.
 *
 * The function mux fixes a hardware UART's roles by pin number, so two
 * identical boards joined by a straight cable put TX against TX. A UART built
 * out of PIO can put either role on either pin. It is a unit here rather than
 * a class of its own so that a program is written against UART either way:
 * someone who learns on a board that needs it should not have to unlearn
 * anything to use a board that does not.
 *
 * The engine lives in the picoruby-pio-uart gem. These are weak, so a build
 * without that gem links and reports the unit as unavailable; the gem's own
 * definitions override them when it is present.
 */
__attribute__((weak)) int
PIO_UART_open(uint8_t tx_pin, uint8_t rx_pin, uint32_t baudrate)
{
  (void)tx_pin; (void)rx_pin; (void)baudrate;
  return -1;
}
__attribute__((weak)) void   PIO_UART_close(void) {}
__attribute__((weak)) bool   PIO_UART_is_open(void) { return false; }
__attribute__((weak)) size_t PIO_UART_write(const uint8_t *d, size_t n)
{ (void)d; return 0; }
__attribute__((weak)) size_t PIO_UART_available(void) { return 0; }
__attribute__((weak)) size_t PIO_UART_read(uint8_t *o, size_t n)
{ (void)o; (void)n; return 0; }
__attribute__((weak)) void   PIO_UART_clear(void) {}
__attribute__((weak)) bool   PIO_UART_take_overflow(void) { return false; }
__attribute__((weak)) uint32_t PIO_UART_set_baudrate(uint32_t b)
{ (void)b; return 0; }
__attribute__((weak)) bool   PIO_UART_is_writable(void) { return false; }
__attribute__((weak)) void   PIO_UART_flush(void) {}

static inline bool
is_pio_unit(int unit_num)
{
  return unit_num == PICORB_UART_PIO_UART0;
}

#define UNIT_SELECT() \
  do { \
    switch (unit_num) { \
      case PICORB_UART_RP2040_UART0: { unit = uart0; break; } \
      case PICORB_UART_RP2040_UART1: { unit = uart1; break; } \
      default: { /* TODO: raise error */ } \
    } \
  } while (0)

/* The IRQ handler is installed once per unit; see UART_open(). */
static bool producer_started[2];

static void
drain_rx_fifo(uart_inst_t *hw, int unit_num)
{
  RingBuffer *rx = UART_unit_rx(unit_num);
  bool stored = false;

  while (uart_is_readable(hw)) {
    uint8_t ch = uart_getc(hw);
    /* Drain the FIFO even with no ring, or the IRQ never deasserts. */
    if (rx && UART_pushBufferAt(rx, ch, time_us_32())) {
      stored = true;
    }
  }
  /* Signal once for the whole burst, and only once something is
     actually there to read: a dropped byte is nothing new to drain. */
  if (stored) {
    UART_signal_rx(unit_num);
  }
}

static void
on_uart0_rx(void)
{
  drain_rx_fifo(uart0, PICORB_UART_RP2040_UART0);
}

static void
on_uart1_rx(void)
{
  drain_rx_fifo(uart1, PICORB_UART_RP2040_UART1);
}

int
UART_unit_name_to_unit_num(const char *name)
{
  if (strcmp(name, "RP2040_UART0") == 0) {
    return PICORB_UART_RP2040_UART0;
  } else if (strcmp(name, "RP2040_UART1") == 0) {
    return PICORB_UART_RP2040_UART1;
  } else if (strcmp(name, "PIO_UART0") == 0) {
    return PICORB_UART_PIO_UART0;
  } else {
    return UART_ERROR_INVALID_UNIT;
  }
}

/*
 * RP2040 GPIO function-select table (valid for RP2350 QFN-60 as well).
 * Each array lists the GPIOs usable as the given UART signal, terminated by -1.
 */
static const int8_t uart0_tx_pins[] = {0, 12, 16, 28, -1};
static const int8_t uart1_tx_pins[] = {4, 8, 20, 24, -1};
static const int8_t uart0_rx_pins[] = {1, 13, 17, 29, -1};
static const int8_t uart1_rx_pins[] = {5, 9, 21, 25, -1};

/* Return the unit that owns pin for the given signal, or -1 if none. */
static int
pin_to_unit(const int8_t *unit0_pins, const int8_t *unit1_pins, int pin)
{
  int i = 0;
  while (unit0_pins[i] != -1) {
    if (unit0_pins[i] == pin) {
      return PICORB_UART_RP2040_UART0;
    }
    i++;
  }
  i = 0;
  while (unit1_pins[i] != -1) {
    if (unit1_pins[i] == pin) {
      return PICORB_UART_RP2040_UART1;
    }
    i++;
  }
  return -1;
}

int
UART_unit_num_from_pins(const char *unit_name, int txd_pin, int rxd_pin)
{
  int candidate = -1;
  if (unit_name && strcmp(unit_name, "PIO_UART0") == 0) {
    return PICORB_UART_PIO_UART0;
  }
  if (0 <= txd_pin) {
    int u = pin_to_unit(uart0_tx_pins, uart1_tx_pins, txd_pin);
    if (u < 0) {
      return UART_ERROR_UNIT_MISMATCH;
    }
    candidate = u;
  }
  if (0 <= rxd_pin) {
    int u = pin_to_unit(uart0_rx_pins, uart1_rx_pins, rxd_pin);
    if (u < 0) {
      return UART_ERROR_UNIT_MISMATCH;
    }
    if (0 <= candidate && candidate != u) {
      return UART_ERROR_UNIT_MISMATCH;
    }
    candidate = u;
  }
  if (unit_name && unit_name[0] != '\0') {
    int name_unit = UART_unit_name_to_unit_num(unit_name);
    if (name_unit < 0) {
      return UART_ERROR_INVALID_UNIT;
    }
    /* Any pin can carry either role on PIO, so the table above says nothing
     * about it and a mismatch against it means nothing either. */
    if (is_pio_unit(name_unit)) {
      return name_unit;
    }
    if (0 <= candidate && candidate != name_unit) {
      return UART_ERROR_UNIT_MISMATCH;
    }
    return name_unit;
  }
  if (candidate < 0) {
    return UART_ERROR_UNDETERMINED;
  }
  return candidate;
}

/*
 * The PIO unit's producer.
 *
 * A hardware UART has an interrupt that fills the ring; PIO has DMA instead,
 * and DMA raises nothing until a transfer ends, which this one never does. So
 * a timer moves bytes from the DMA ring into the ring UART reads from, and
 * signals the event bridge so that UART#irq behaves the same as it does on a
 * hardware unit.
 *
 * A millisecond is latency, not loss: the DMA ring holds 512 bytes whether or
 * not anything comes to collect them, which was the whole reason for it.
 */
/* Driven from a hardware alarm through the timer registers, the same way
 * picoruby-machine drives its millisecond tick. Whichever alarm is free: 0 is
 * that tick, 1 and 2 go to picoruby-psg, and 3 is the SDK's default alarm
 * pool -- claiming a taken one panics, so ask for an unused one. */
#define PIO_PRODUCER_INTERVAL_US 1000

static int pio_producer_alarm = -1;

static void
pio_producer_rearm(void)
{
  timer_hw->alarm[pio_producer_alarm] =
    timer_hw->timerawl + PIO_PRODUCER_INTERVAL_US;
  hw_clear_bits(&timer_hw->intr, 1u << pio_producer_alarm);
}

static void
pio_producer(void)
{
  pio_producer_rearm();

  RingBuffer *rx = UART_unit_rx(PICORB_UART_PIO_UART0);
  uint8_t chunk[64];
  bool stored = false;

  size_t n;
  while (0 < (n = PIO_UART_read(chunk, sizeof(chunk)))) {
    uint32_t now = time_us_32();
    for (size_t i = 0; i < n; i++) {
      /* Read it out of the DMA ring either way: leaving it there only means
       * losing something newer instead. */
      if (rx && UART_pushBufferAt(rx, chunk[i], now)) {
        stored = true;
      }
    }
    if (n < sizeof(chunk)) break;
  }
  if (stored) {
    UART_signal_rx(PICORB_UART_PIO_UART0);
  }
}

static void
pio_producer_start(void)
{
  if (0 <= pio_producer_alarm) return;
  int alarm = hardware_alarm_claim_unused(false);
  if (alarm < 0) return;   /* no alarm left: the unit then never delivers */
  pio_producer_alarm = alarm;
  uint irq = timer_hardware_alarm_get_irq_num(timer_hw, (uint)alarm);
  hw_set_bits(&timer_hw->inte, 1u << alarm);
  irq_set_exclusive_handler(irq, pio_producer);
  irq_set_enabled(irq, true);
  pio_producer_rearm();
}

void
UART_open(int unit_num, uint32_t txd_pin, uint32_t rxd_pin)
{
  uart_inst_t *unit = NULL;

  if (is_pio_unit(unit_num)) {
    if (PIO_UART_open((uint8_t)txd_pin, (uint8_t)rxd_pin, DEFAULT_BAUDRATE)
          == 0) {
      pio_producer_start();
    }
    return;
  }

  if (unit_num < 0 || PICORB_UART_PIO_UART0 <= unit_num) {
    return;
  }
  UNIT_SELECT();

  /* uart_init() resets the UART block, which clears IMSC and so turns
     the RX interrupt back off. It must therefore run only where the
     interrupt is (re-)armed straight afterwards -- doing it on every
     open would leave a reopened unit with a producer that never fires.
     Baudrate and format are not lost either way: UART#initialize sets
     them right after this returns. */
  if (!producer_started[unit_num]) {
    uint irq;

    uart_init(unit, DEFAULT_BAUDRATE);
    if (unit_num == PICORB_UART_RP2040_UART0) {
      irq = UART0_IRQ;
      irq_set_exclusive_handler(irq, on_uart0_rx);
    } else {
      irq = UART1_IRQ;
      irq_set_exclusive_handler(irq, on_uart1_rx);
    }
    irq_set_enabled(irq, true);
    uart_set_irq_enables(unit, true, false);
    producer_started[unit_num] = true;
  }

  /* Pins are per open, so a second UART.new can move them. */
  gpio_set_function(txd_pin, GPIO_FUNC_UART);
  gpio_set_function(rxd_pin, GPIO_FUNC_UART);
}

uint32_t
UART_set_baudrate(int unit_num, uint32_t baudrate)
{
  if (is_pio_unit(unit_num)) {
    return PIO_UART_set_baudrate(baudrate);
  }
  uart_inst_t *unit = NULL;
  UNIT_SELECT();
  return uart_set_baudrate(unit, baudrate);
}

void
UART_set_flow_control(int unit_num, bool cts, bool rts)
{
  /* PIO carries data and nothing else: no RTS, no CTS. */
  if (is_pio_unit(unit_num)) {
    (void)cts; (void)rts;
    return;
  }
  uart_inst_t *unit = NULL;
  UNIT_SELECT();
  uart_set_hw_flow(unit, cts, rts);
}

void
UART_set_format(int unit_num, uint32_t data_bits, uint32_t stop_bits, uint8_t parity)
{
  /* The PIO programs are 8N1 and only 8N1, which is what UART#initialize
   * asks for by default. Another format is quietly not applied. */
  if (is_pio_unit(unit_num)) {
    (void)data_bits; (void)stop_bits; (void)parity;
    return;
  }
  uart_inst_t *unit = NULL;
  UNIT_SELECT();
  uart_set_format(unit, data_bits, stop_bits, (uart_parity_t)parity);
}

void
UART_set_function(uint32_t pin)
{
  gpio_set_function(pin, GPIO_FUNC_UART);
}

bool
UART_is_writable(int unit_num)
{
  if (is_pio_unit(unit_num)) {
    return PIO_UART_is_writable();
  }
  uart_inst_t *unit = NULL;
  UNIT_SELECT();
  return uart_is_writable(unit);
}

void
UART_write_blocking(int unit_num, const uint8_t *src, size_t len)
{
  if (is_pio_unit(unit_num)) {
    PIO_UART_write(src, len);
    return;
  }
  uart_inst_t *unit = NULL;
  UNIT_SELECT();
  uart_write_blocking(unit, src, len);
}

bool
UART_is_readable(int unit_num)
{
  /* Everything that arrived is in the ring already: the producer above
   * emptied the DMA buffer into it. Reading from here as well would take
   * bytes out from under it. */
  if (is_pio_unit(unit_num)) {
    return false;
  }
  uart_inst_t *unit = NULL;
  UNIT_SELECT();
  return uart_is_readable(unit);
}

size_t
UART_read_nonblocking(int unit_num, uint8_t *dst, size_t maxlen)
{
  if (is_pio_unit(unit_num)) {
    (void)dst; (void)maxlen;
    return 0;
  }
  size_t actual_len = 0;
  uart_inst_t *unit = NULL;
  UNIT_SELECT();
  while (uart_is_readable(unit)) {
    dst[actual_len++] = uart_getc(unit);
    if (maxlen <= actual_len) {
      break;
    }
  }
  return actual_len;
}

void
UART_break(int unit_num, uint32_t interval)
{
  /* The PIO transmit program has no way to hold the line low. */
  if (is_pio_unit(unit_num)) {
    (void)interval;
    return;
  }
  uart_inst_t *unit = NULL;
  UNIT_SELECT();
  uart_set_break(unit, true);
  sleep_ms(interval);
  uart_set_break(unit, false);
}

void
UART_flush(int unit_num)
{
  if (is_pio_unit(unit_num)) {
    PIO_UART_flush();
    return;
  }
  uart_inst_t *unit = NULL;
  UNIT_SELECT();
  uart_tx_wait_blocking(unit);
}

void
UART_clear_rx_buffer(int unit_num)
{
  uart_inst_t *unit = NULL;
  if (is_pio_unit(unit_num)) {
    PIO_UART_clear();
    return;
  }
  UNIT_SELECT();
  while (uart_is_readable(unit)) {
    uart_getc(unit);
  }
}

void
UART_clear_tx_buffer(int unit_num)
{
  // no-op
}
