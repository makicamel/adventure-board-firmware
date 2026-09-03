#include <mruby.h>
#include <mruby/class.h>
#include <mruby/error.h>
#include <mruby/presym.h>
#include <mruby/string.h>

/* There is one GROVE-B, so there is one link, and its state lives in the port
 * rather than on the object. A second PIOUART reports itself busy. */

static void
raise_on_error(mrb_state *mrb, int err)
{
  switch (err) {
    case PIO_UART_OK:
      return;
    case PIO_UART_E_BUSY:
      mrb_raise(mrb, E_RUNTIME_ERROR, "PIO UART is already open");
    case PIO_UART_E_NO_SM:
      mrb_raise(mrb, E_RUNTIME_ERROR, "no free PIO state machine");
    case PIO_UART_E_NO_DMA:
      mrb_raise(mrb, E_RUNTIME_ERROR, "no free DMA channel");
    default:
      mrb_raise(mrb, E_RUNTIME_ERROR, "PIO UART is closed");
  }
}

static mrb_value
mrb_pio_uart_open(mrb_state *mrb, mrb_value self)
{
  mrb_int tx_pin, rx_pin, baudrate;
  mrb_get_args(mrb, "iii", &tx_pin, &rx_pin, &baudrate);
  raise_on_error(mrb, PIO_UART_open((uint8_t)tx_pin, (uint8_t)rx_pin,
                                    (uint32_t)baudrate));
  return self;
}

static mrb_value
mrb_pio_uart_close(mrb_state *mrb, mrb_value self)
{
  PIO_UART_close();
  return mrb_nil_value();
}

static mrb_value
mrb_pio_uart_write(mrb_state *mrb, mrb_value self)
{
  const char *str;
  mrb_int len;
  mrb_get_args(mrb, "s", &str, &len);
  return mrb_fixnum_value((mrb_int)PIO_UART_write((const uint8_t *)str,
                                                  (size_t)len));
}

static mrb_value
mrb_pio_uart_bytes_available(mrb_state *mrb, mrb_value self)
{
  return mrb_fixnum_value((mrb_int)PIO_UART_available());
}

/* read       -> everything waiting, or nil
 * read(max)  -> at most max bytes, or nil */
static mrb_value
mrb_pio_uart_read(mrb_state *mrb, mrb_value self)
{
  mrb_int max = -1;
  mrb_get_args(mrb, "|i", &max);
  size_t want = PIO_UART_available();
  if (0 <= max && (size_t)max < want) want = (size_t)max;
  if (want == 0) return mrb_nil_value();

  mrb_value str = mrb_str_new(mrb, NULL, (mrb_int)want);
  size_t got = PIO_UART_read((uint8_t *)RSTRING_PTR(str), want);
  if (got != want) mrb_str_resize(mrb, str, (mrb_int)got);
  return got == 0 ? mrb_nil_value() : str;
}

static mrb_value
mrb_pio_uart_clear_rx_buffer(mrb_state *mrb, mrb_value self)
{
  PIO_UART_clear();
  return mrb_nil_value();
}

static mrb_value
mrb_pio_uart_rx_overflow(mrb_state *mrb, mrb_value self)
{
  return mrb_bool_value(PIO_UART_take_overflow());
}

static mrb_value
mrb_pio_uart_buffer_size(mrb_state *mrb, mrb_value self)
{
  return mrb_fixnum_value((mrb_int)PIO_UART_buffer_size());
}

void
mrb_picoruby_pio_uart_gem_init(mrb_state *mrb)
{
  struct RClass *class_PIOUART = mrb_define_class_id(mrb, MRB_SYM(PIOUART),
                                                     mrb->object_class);

  mrb_define_method_id(mrb, class_PIOUART, MRB_SYM(_open),
                       mrb_pio_uart_open, MRB_ARGS_REQ(3));
  mrb_define_method_id(mrb, class_PIOUART, MRB_SYM(close),
                       mrb_pio_uart_close, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, class_PIOUART, MRB_SYM(write),
                       mrb_pio_uart_write, MRB_ARGS_REQ(1));
  mrb_define_method_id(mrb, class_PIOUART, MRB_SYM(bytes_available),
                       mrb_pio_uart_bytes_available, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, class_PIOUART, MRB_SYM(read),
                       mrb_pio_uart_read, MRB_ARGS_OPT(1));
  mrb_define_method_id(mrb, class_PIOUART, MRB_SYM(clear_rx_buffer),
                       mrb_pio_uart_clear_rx_buffer, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, class_PIOUART, MRB_SYM_Q(rx_overflow),
                       mrb_pio_uart_rx_overflow, MRB_ARGS_NONE());
  mrb_define_method_id(mrb, class_PIOUART, MRB_SYM(buffer_size),
                       mrb_pio_uart_buffer_size, MRB_ARGS_NONE());
}

void
mrb_picoruby_pio_uart_gem_final(mrb_state *mrb)
{
  PIO_UART_close();
}
