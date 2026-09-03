#include "../include/pio_uart.h"

#if defined(PICORB_VM_MRUBY)

#include "mruby/pio_uart.c"

#elif defined(PICORB_VM_MRUBYC)

#include "mrubyc/pio_uart.c"

#endif
