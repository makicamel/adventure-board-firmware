#ifndef PICORB_PIO_UART_H_
#define PICORB_PIO_UART_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  PIO_UART_OK        =  0,
  PIO_UART_E_BUSY    = -1,  /* no longer returned: a second open moves the link */
  PIO_UART_E_NO_SM   = -2,  /* no free state machine or no room for the program */
  PIO_UART_E_NO_DMA  = -3,  /* no free DMA channel */
  PIO_UART_E_CLOSED  = -4
} pio_uart_error_t;

int    PIO_UART_open(uint8_t tx_pin, uint8_t rx_pin, uint32_t baudrate);
uint32_t PIO_UART_set_baudrate(uint32_t baudrate);
bool   PIO_UART_is_writable(void);
void   PIO_UART_flush(void);
void   PIO_UART_close(void);
bool   PIO_UART_is_open(void);

size_t PIO_UART_write(const uint8_t *data, size_t len);
size_t PIO_UART_available(void);
size_t PIO_UART_read(uint8_t *out, size_t max);
void   PIO_UART_clear(void);

/* True if bytes were lost because nothing read for too long. Sticky until
 * read, which is the whole point: a poll that misses is otherwise silent. */
bool   PIO_UART_take_overflow(void);
size_t PIO_UART_buffer_size(void);

#ifdef __cplusplus
}
#endif

#endif /* PICORB_PIO_UART_H_ */
