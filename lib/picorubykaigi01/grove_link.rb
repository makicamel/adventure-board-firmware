# A serial link between two of these boards over GROVE-B.
#
# The pin mux fixes UART0's roles by pin number: GPIO28 can only be TX and
# GPIO29 only RX. Two boards joined by a straight Grove cable therefore put TX
# against TX, and the hardware UART cannot help. PIO can put a UART on either
# pin, so the board that takes the :b role transmits on 29 and listens on 28,
# and the cable that came in the box works.
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
# The programs below are the ones in pico-sdk's uart_tx.pio and uart_rx.pio,
# written in picoruby-pio's assembler. One bit is eight state machine cycles,
# so the clock is the baud rate times eight.
require 'pio'

class GroveLink
  DEFAULT_BAUDRATE = 115_200
  CYCLES_PER_BIT = 8

  # Send: pull a byte and hold the line high (stop bit / idle), drop it for a
  # start bit, then shift eight bits out, least significant first.
  def self.tx_program
    PIO.asm(side_set: 1, side_set_optional: true) do
      wrap_target
      pull                        side: 1, delay: 7
      set :x, 7,                  side: 0, delay: 7
      label :bitloop
      out :pins, 1
      jmp :bitloop, cond: :x_dec, delay: 6
      wrap
    end
  end

  # Receive: wait for the start bit, then wait ten more cycles so the first
  # data bit is sampled in the middle rather than at its edge. Autopush hands
  # the byte over once eight bits are in.
  def self.rx_program
    PIO.asm do
      wrap_target
      wait 0, :pin, 0
      set :x, 7,                  delay: 10
      label :bitloop
      in_ :pins, 1
      jmp :bitloop, cond: :x_dec, delay: 6
      wrap
    end
  end

  # One instruction, assembled on its own, to force the TX pin high before the
  # state machine starts running. Without it the pin is an output sitting at
  # zero, which the other board reads as a break.
  def self.drive_high
    PIO.asm { set :pins, 1 }.instructions[0]
  end

  # tx_pin and rx_pin may be the same pin: PIO reads the pad it is driving, so
  # that gives a loopback with no wire at all, which is how this was first
  # tested.
  def initialize(tx_pin:, rx_pin:, baudrate: DEFAULT_BAUDRATE,
                 pio: PIO::PIO0, tx_sm: 0, rx_sm: 1)
    freq = baudrate * CYCLES_PER_BIT

    # The line idles high, and nothing else holds it there while the other
    # board is unplugged.
    GPIO.new(rx_pin, GPIO::IN | GPIO::PULL_UP)

    # Each state machine has a pair of four-word FIFOs and uses only one of
    # them, so give each the other's. Eight bytes is not much, but it is twice
    # as much, and it is all the buffering there is: nothing on this side runs
    # between polls to empty it.
    @tx = PIO::StateMachine.new(
      pio: pio, sm: tx_sm, program: self.class.tx_program, freq: freq,
      out_pins: tx_pin, out_pin_count: 1,
      sideset_pins: tx_pin,
      out_shift_right: true, out_shift_autopull: false, out_shift_threshold: 32,
      fifo_join: PIO::FIFO_JOIN_TX
    )
    @rx = PIO::StateMachine.new(
      pio: pio, sm: rx_sm, program: self.class.rx_program, freq: freq,
      in_pins: rx_pin,
      in_shift_right: true, in_shift_autopush: true, in_shift_threshold: 8,
      fifo_join: PIO::FIFO_JOIN_RX
    )

    @tx.exec(self.class.drive_high)
    @tx.start
    @rx.start
    @lines = []
    @partial = ""
    flush_input
  end

  # Whatever arrived while the other board was starting up is not a message.
  def flush_input
    @rx.clear_fifos
    @lines = []
    @partial = ""
    nil
  end

  # Move everything the hardware has into Ruby, where there is room for it.
  #
  # Call this often. The receive FIFO holds eight bytes and there is no
  # interrupt behind it, so anything that arrives while it is full is simply
  # gone -- a program that sleeps between polls has to keep its messages
  # shorter than that.
  def pump
    while (word = @rx.get_nonblocking)
      char = ((word >> 24) & 0xFF).chr
      if char == "\n"
        @lines << @partial
        @partial = ""
      elsif char != "\r"
        # Append in place. `@partial += char` builds a new string every byte,
        # which turns a long line into quadratic work and was most of why this
        # ran at a fifth of the line rate.
        @partial << char
      end
    end
    nil
  end

  CHUNK = 4

  # Sending eight bytes fills the transmit FIFO, and on a loopback -- or when
  # the other board answers immediately -- the receive side fills at the same
  # rate. So empty it as we go, in chunks: byte at a time paid for a string
  # object per byte, and half the receive FIFO is margin enough.
  def write(string)
    i = 0
    length = string.length
    while i < length
      @tx.put_bytes(string[i, CHUNK])
      pump
      i += CHUNK
    end
    length
  end

  def puts(string)
    write(string + "\n")
  end

  # --- the raw pair --------------------------------------------------------
  #
  # write_raw and read_byte leave the line buffer alone. write/puts/gets use
  # it. Pick one pair and stay there: write() empties the receive FIFO into
  # the line buffer as it goes, so a program that writes with it and reads
  # with read_byte will find its own sends eating the other board's bytes.

  def write_raw(string)
    @tx.put_bytes(string)
    string.length
  end

  # One byte straight from the hardware, or nil.
  def read_byte
    word = @rx.get_nonblocking
    return nil unless word
    (word >> 24) & 0xFF
  end

  # A whole line, or nil if one has not finished arriving. Never blocks: a
  # program calls this in its loop the same way it polls its buttons.
  def gets
    pump
    @lines.shift
  end

  def close
    @tx.stop
    @rx.stop
    nil
  end
end
