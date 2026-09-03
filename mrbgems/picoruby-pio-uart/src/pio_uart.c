/*
 * This gem has no Ruby side.
 *
 * It is reached through UART, as the unit named "PIO_UART0", so that a program
 * written for this board is written against the same class as a program
 * written for any other PicoRuby board. The engine is in
 * ports/rp2040/pio_uart.c, and picoruby-uart's RP2 port calls into it.
 *
 * The gem hooks below are what the build expects of every gem; there is
 * nothing to register.
 */
#include "../include/pio_uart.h"

#if defined(PICORB_VM_MRUBY)

#include <mruby.h>

void
mrb_picoruby_pio_uart_gem_init(mrb_state *mrb)
{
  (void)mrb;
}

void
mrb_picoruby_pio_uart_gem_final(mrb_state *mrb)
{
  (void)mrb;
}

#endif
