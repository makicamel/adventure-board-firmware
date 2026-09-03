# A serial link between two of these boards over GROVE-B.
#
# The pin mux fixes UART0's roles by pin number: GPIO28 can only be TX and
# GPIO29 only RX. Two boards joined by a straight Grove cable therefore put TX
# against TX, and the hardware UART cannot help. The picoruby-pio-uart gem
# builds a UART out of PIO instead, where either pin can do either job, so the
# board that takes the :b role transmits on 29 and listens on 28 and the cable
# that came in the box works.
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
  DEFAULT_BAUDRATE = PIOUART::DEFAULT_BAUDRATE

  def initialize(tx_pin:, rx_pin:, baudrate: DEFAULT_BAUDRATE)
    @uart = PIOUART.new(tx_pin: tx_pin, rx_pin: rx_pin, baudrate: baudrate)
    @lines = []
    @partial = ""
    flush_input
  end

  # Whatever arrived while the other board was starting up is not a message.
  def flush_input
    @uart.clear_rx_buffer
    @lines = []
    @partial = ""
    nil
  end

  # Move what the buffer holds into finished lines. #gets does this, so a
  # program only calls it directly to keep the buffer short while it is busy.
  def pump
    while (chunk = @uart.read)
      i = 0
      while i < chunk.length
        char = chunk[i]
        if char == "\n"
          @lines << @partial
          @partial = ""
        elsif char != "\r"
          @partial << char
        end
        i += 1
      end
    end
    nil
  end

  def write(string)
    @uart.write(string)
  end

  def puts(string)
    write(string + "\n")
  end

  # A whole line, or nil if one has not finished arriving. Never blocks: a
  # program calls this in its loop the same way it polls its buttons.
  def gets
    pump
    @lines.shift
  end

  # True once if the other board sent more than 512 bytes than we read in
  # time, which means something is missing. Clears when asked.
  def lost?
    @uart.rx_overflow?
  end

  def close
    @uart.close
    nil
  end
end
