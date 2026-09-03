# A UART on PIO, received into a DMA ring buffer.
#
# The pin mux fixes the hardware UART's roles by pin number, so two identical
# boards joined by a straight cable put transmit against transmit. PIO can put
# a UART on either pin, which is what this is for.
#
#   uart = PIOUART.new(tx_pin: 28, rx_pin: 29)
#   uart.write("hello\n")
#   while (chunk = uart.read)
#     ...
#   end
#
# The receive side is filled by DMA, not by Ruby, so a slow loop costs latency
# rather than data. Only falling a whole buffer behind loses anything, and
# #rx_overflow? says so when it happens.
class PIOUART
  DEFAULT_BAUDRATE = 115_200

  def initialize(tx_pin:, rx_pin:, baudrate: DEFAULT_BAUDRATE)
    _open(tx_pin, rx_pin, baudrate)
  end
end
