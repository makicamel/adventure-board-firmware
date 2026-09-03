# picoruby-pio-uart

A UART built out of PIO, with the receive side filled by DMA.

```ruby
uart = PIOUART.new(tx_pin: 28, rx_pin: 29, baudrate: 115_200)
uart.write("hello\n")
while (chunk = uart.read)
  # ...
end
puts "fell behind" if uart.rx_overflow?
```

## Why not the hardware UART

The RP2040/RP2350 pin mux fixes a UART's roles by pin number: a pin whose
number is a multiple of four can only be TX and the next one only RX. Two
identical boards joined by a straight cable therefore put TX against TX.
PIO can put either role on either pin, which is the point.

## Why not just PIO

A PIO state machine has a four word FIFO, eight if given the one it does not
use, and **nothing behind it**. Whatever arrives while it is full is gone,
with no overrun flag to find it by. Polling that from Ruby is a bet that no
garbage collection, no I2C write and no other task ever delays the next look
by more than eight byte times — 700µs at 115200. It is not a bet worth making.

So the receive path never touches the processor:

- the state machine hands each byte to DMA
- DMA writes it into a 512 byte ring whose address wraps in hardware
  (`channel_config_set_ring`)
- a second DMA channel, chained to the first, writes the transfer count back
  so the transfer never finishes

Ruby reads from the ring at whatever pace it likes. Only falling a whole
buffer behind loses anything, and `rx_overflow?` says so.

Transmit is a blocking write into the transmit FIFO: nothing is lost there
because we set the pace. 57 bytes at 115200 takes about 5ms.

## Limits

- **One instance.** The buffer is static and aligned to its own size, which is
  what lets the DMA wrap it. A second `PIOUART.new` raises.
- **RP2040 / RP2350 only.** It is PIO and DMA.

## Careful

On **RP2350** the top four bits of a DMA channel's `TRANS_COUNT` are a MODE
field, and `0xf` means ENDLESS: the channel runs forever and **does not
decrement the count**. On RP2040 those bits are part of the count, so every
RP2040 example writes `0xffffffff` there. Copy that onto RP2350 and the
buffer fills correctly while the count insists nothing has arrived. This uses
`0x0fffffff`, which is MODE=NORMAL with the largest count there is.
