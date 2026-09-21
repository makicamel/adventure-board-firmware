#ifndef ADC_CAPTURE_DEFINED_H_
#define ADC_CAPTURE_DEFINED_H_

#include <stdint.h>
#include <stdbool.h>

/* 2^15 bytes, one byte a sample (the ADC's upper 8 bits). 2^16 does not
 * fit: R2P2 on the RP2350 has about 58 KB of RAM left beside its heap. */
#define ADC_CAPTURE_RING_BITS 15
#define ADC_CAPTURE_SIZE      (1u << ADC_CAPTURE_RING_BITS)

bool     ADC_capture_start(uint8_t pin, uint32_t rate_hz);
/* Stops and returns where the next sample would have gone: the oldest one. */
uint32_t ADC_capture_stop(void);
uint32_t ADC_capture_addr(void);

#endif
