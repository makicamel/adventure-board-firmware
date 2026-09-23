# A serial link between two of these boards over GROVE-B.
#
# The pin mux fixes UART0's roles by pin number: GPIO28 can only be TX and
# GPIO29 only RX. Two boards joined by a straight Grove cable therefore put TX
# against TX. So this asks UART for its PIO unit instead, where either pin can
# do either job, and the board that takes the :b role transmits on 29 and
# listens on 28 -- the cable that came in the box works.
#
# It is an ordinary UART. Everything below is what any PicoRuby program does
# with one, and everything a program learns here it can take to a board that
# has no LED matrix and no Grove socket.
#
#   link = board.grove_link(role: :a)
#   link.puts "hello"
#   while line = link.gets
#     ...
#   end
#
# Both boards run this same code; only the role differs. Neither should
# transmit until a role is chosen, because two boards on the same role drive
# the same wire against each other.
#
# Receiving costs nothing here: the gem's DMA fills a 512 byte buffer without
# the processor, so a loop that goes away for half a second comes back to find
# everything still waiting. Only falling a whole buffer behind loses anything,
# and #lost? says so rather than letting it pass in silence.
class GroveLink
  DEFAULT_BAUDRATE = 115_200

  # The UART itself, for anything this class does not wrap. It answers every
  # method a hardware UART answers, #irq included.
  attr_reader :uart

  # UART's own ring defaults to 256 bytes, which is smaller than the DMA ring
  # feeding it -- so a burst that the hardware caught would be dropped on the
  # way through. A kilobyte is about eighteen of these messages.
  RX_BUFFER_SIZE = 1024

  def initialize(tx_pin:, rx_pin:, baudrate: DEFAULT_BAUDRATE,
                 rx_buffer_size: RX_BUFFER_SIZE)
    @uart = UART.new(unit: :PIO_UART0, txd_pin: tx_pin, rxd_pin: rx_pin,
                     baudrate: baudrate, rx_buffer_size: rx_buffer_size)
    flush_input
  end

  # Whatever arrived while the other board was starting up is not a message.
  def flush_input
    @uart.clear_rx_buffer
    nil
  end

  def write(string)
    @uart.write(string)
  end

  def puts(string)
    @uart.write(string + "\n")
  end

  # A whole line, or nil if one has not finished arriving. Never blocks: a
  # program calls this in its loop the same way it polls its buttons.
  def gets
    line = @uart.gets
    line && line.chomp
  end

  # How many times the buffer filled before anything came to read it, which
  # means bytes are missing. Zero unless something went badly wrong.
  def lost
    @uart.rx_overflow_count
  end
end
