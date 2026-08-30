# Simulation core for the picorubykaigi01 LED matrix.
#
# Deliberately free of any JS dependency: everything that is interesting here —
# decoding register writes and composing two chips into one 16x16 panel — can
# then be exercised headless with bin/picoruby, and the browser only adds the
# picture. See sim/test/panel_test.rb.

# The driver opens with `require 'i2c'`, which finds the built-in gem on real
# firmware. Neither bin/picoruby nor the browser has that gem, so the require
# has to be tolerated. Picotest's runner does the same thing for the same
# reason. This file therefore has to be loaded *before* the driver.
unless $sim_require_patched
  $sim_require_patched = true
  module Kernel
    alias :require_before_sim :require
    def require(name)
      return require_before_sim(name)
    rescue LoadError
      false
    end
  end
end

# Stand-in for picoruby-i2c. The real gem is a C extension with no posix or
# wasm port, so the browser has no I2C at all and this name is free. Writes are
# routed to whichever virtual chip answers the address, which is what lets the
# unmodified driver from mrbgems/picoruby-is31fl3729 run here.
class I2C
  def initialize(unit: nil, frequency: 100_000, sda_pin: -1, scl_pin: -1, timeout: 1000)
    @devices = {}
  end

  def attach(address, device)
    @devices[address] = device
    device
  end

  def write(address, *outputs, timeout: nil, nostop: false)
    bytes = flatten(outputs)
    device = @devices[address]
    device.receive(bytes) if device
    bytes.bytesize
  end

  def read(address, len, *outputs, timeout: nil)
    device = @devices[address]
    return "\x00" * len unless device
    device.transmit(flatten(outputs), len)
  end

  def scan(timeout: nil)
    nil
  end

  private

  def flatten(outputs)
    bytes = ""
    i = 0
    while i < outputs.size
      out = outputs[i]
      if out.is_a?(Integer)
        bytes << out.chr
      elsif out.is_a?(String)
        bytes << out
      elsif out.is_a?(Array)
        j = 0
        while j < out.size
          bytes << out[j].to_i.chr
          j += 1
        end
      end
      i += 1
    end
    bytes
  end
end

# Stand-in for picoruby-gpio, which is a C extension with no wasm port. Pin
# state lives in a class-level table so the page can press and release buttons
# without reaching into whatever object happens to hold them.
#
# Unconnected pins read high, which is what the board's 10k pull-ups do.
class GPIO
  IN         = 1
  OUT        = 2
  HIGH_Z     = 4
  PULL_UP    = 8
  PULL_DOWN  = 16
  OPEN_DRAIN = 32
  ALT        = 64

  # Edge and level constants, as picoruby-irq adds them to GPIO.
  LEVEL_LOW  = 1
  LEVEL_HIGH = 2
  EDGE_FALL  = 4
  EDGE_RISE  = 8

  def self.state
    @state ||= {}
  end

  # Edge handlers registered through GPIO#irq, keyed by pin.
  def self.handlers
    @handlers ||= {}
  end

  def self.reset
    @state = {}
    @handlers = {}
    nil
  end

  def self.read_at(pin)
    v = state[pin]
    v.nil? ? 1 : v
  end

  def self.write_at(pin, value)
    state[pin] = (value == 0) ? 0 : 1
    0
  end

  # What the page calls. The buttons are wired active low, so a press pulls the
  # pin down. The edge is delivered straight to whoever registered for it —
  # there is nothing to poll and nothing to miss, which is what the real chip's
  # interrupt does.
  def self.press(pin)
    return 0 if read_at(pin) == 0
    write_at(pin, 0)
    fire(pin, EDGE_FALL)
    0
  end

  def self.release(pin)
    return 0 if read_at(pin) == 1
    write_at(pin, 1)
    fire(pin, EDGE_RISE)
    0
  end

  def self.fire(pin, event_type)
    list = handlers[pin]
    return nil unless list
    i = 0
    while i < list.size
      # Only the handlers that asked for this edge.
      list[i][0].call(nil, event_type) if (list[i][1] & event_type) != 0
      i += 1
    end
    nil
  end

  attr_reader :pin, :flags

  def initialize(pin, flags = IN, alt_function = 0)
    @pin = pin
    @flags = flags
  end

  def setmode(flags, alt_function = 0)
    @flags = flags
    0
  end

  def read
    GPIO.read_at(@pin)
  end

  def write(value)
    GPIO.write_at(@pin, value)
  end

  def high?
    read == 1
  end

  def low?
    read == 0
  end

  # Stand-in for GPIO#irq from picoruby-irq. The debounce argument is accepted
  # and ignored: the page produces clean events, and the gem does the filtering
  # on the board.
  def irq(event_type, debounce: nil, capture: nil, &block)
    (GPIO.handlers[@pin] ||= []) << [block, event_type]
    block
  end
end

# Stand-in for picoruby-irq. Only what the board layer touches: the page
# delivers edges synchronously, so there is no dispatcher to start.
module IRQ
  def self.start
    true
  end

  def self.stop
    true
  end

  def self.process(_max = nil)
    0
  end
end

# A virtual IS31FL3729. It holds the registers the driver actually writes and
# reports a brightness per dot, so that leaving the chip half-initialised looks
# on screen the way it would look on a bench: dark.
class VirtualIS31FL3729
  PWM_BASE        = 0x01
  SCALING_BASE    = 0x90
  CONFIGURATION   = 0xA0
  GLOBAL_CURRENT  = 0xA1
  RESET           = 0xCF
  RESET_VALUE     = 0xAE

  SSD = 0x01

  SCALING_COUNT = 16
  ROW_STRIDE    = 0x10

  attr_reader :rows, :columns

  def initialize(rows: 8)
    @rows = rows
    @columns = (rows == 9) ? 15 : 16
    power_on_reset
  end

  def power_on_reset
    # Everything comes up at zero, global current and scaling included, which
    # is why a chip that is only reset stays dark.
    @pwm = "\x00" * (@rows * ROW_STRIDE)
    @scaling = "\x00" * SCALING_COUNT
    @configuration = 0x00
    @global_current = 0x00
    nil
  end

  # One I2C write: a register address followed by any number of data bytes,
  # which the chip stores at consecutive addresses.
  def receive(bytes)
    return nil if bytes.bytesize < 1
    address = bytes.getbyte(0) || 0
    i = 1
    size = bytes.bytesize
    while i < size
      store(address + i - 1, bytes.getbyte(i) || 0)
      i += 1
    end
    nil
  end

  def transmit(_written, len)
    "\x00" * len
  end

  def enabled?
    (@configuration & SSD) != 0
  end

  def global_current
    @global_current
  end

  def pwm_at(sw, cs)
    return 0 if sw < 1 || @rows < sw || cs < 1 || @columns < cs
    @pwm.getbyte((sw - 1) * ROW_STRIDE + cs - 1) || 0
  end

  def scaling_at(cs)
    @scaling.getbyte(cs - 1) || 0
  end

  # 0.0 .. 1.0. An approximation of how bright the dot looks, not a photometric
  # model: the point is that the three things which can leave a dot dark (PWM,
  # global current, per-column scaling) all show up.
  def brightness_at(sw, cs)
    return 0.0 unless enabled?
    gcc = @global_current
    gcc = 0x40 if 0x40 < gcc
    return 0.0 if gcc == 0
    pwm_at(sw, cs).to_f / 255.0 * gcc.to_f / 64.0 * scaling_at(cs).to_f / 255.0
  end

  private

  def store(address, value)
    if address == RESET
      power_on_reset if value == RESET_VALUE
    elsif address == CONFIGURATION
      @configuration = value
    elsif address == GLOBAL_CURRENT
      @global_current = value
    elsif SCALING_BASE <= address && address < SCALING_BASE + SCALING_COUNT
      @scaling.setbyte(address - SCALING_BASE, value)
    elsif PWM_BASE <= address && address - PWM_BASE < @pwm.bytesize
      @pwm.setbyte(address - PWM_BASE, value)
    end
    nil
  end
end

# The simulated panel: what the two chips add up to, seen from the front.
#
# The coordinate composition here mirrors LedMatrix in lib/picorubykaigi01.rb
# rather than being shared with it: LedMatrix drives the chips and this reads
# them, so keeping the two independent is what makes the test meaningful. Rows
# 1..8 are U10 at 0x34 and rows 9..16 are U11 at 0x35, whose columns are wired
# in reverse. See dev-docs/led-matrix-gem/hardware.md section 4.
class Panel
  WIDTH  = 16
  HEIGHT = 16

  TOP_ADDRESS    = 0x34
  BOTTOM_ADDRESS = 0x35

  # 0x00 .. 0xFF as two lowercase hex digits, built once.
  HEX = begin
    digits = "0123456789abcdef"
    table = []
    i = 0
    while i < 256
      table << (digits[i >> 4].to_s + digits[i & 0x0F].to_s)
      i += 1
    end
    table
  end

  # The enable pin both chips share. Modelled because it is easy to forget and
  # the failure it causes on a bench — a panel that stays dark although every
  # register is right — is exactly the one worth reproducing.
  SDB_PIN = 24

  attr_reader :i2c, :top, :bottom

  def initialize
    @i2c = I2C.new
    @top = VirtualIS31FL3729.new
    @bottom = VirtualIS31FL3729.new
    @i2c.attach(TOP_ADDRESS, @top)
    @i2c.attach(BOTTOM_ADDRESS, @bottom)
  end

  def enabled?
    GPIO.read_at(SDB_PIN) == 1
  end

  # Which chip, row and column drive the pixel at (x, y). x and y are 1-based
  # with x = 1 at one end of the columns and y = 1 at one end of the rows; which
  # physical end that is stays open until a dot is lit on real hardware.
  def locate(x, y)
    if y <= 8
      [@top, y, x]
    else
      [@bottom, y - 8, WIDTH + 1 - x]
    end
  end

  def brightness(x, y)
    return 0.0 if x < 1 || WIDTH < x || y < 1 || HEIGHT < y
    return 0.0 unless enabled?
    chip, sw, cs = locate(x, y)
    chip.brightness_at(sw, cs)
  end

  # Two hex digits per dot, row major from (1, 1): 512 characters for the whole
  # panel. This is what the renderer is handed.
  #
  # It is a String rather than the Array that reads more naturally because the
  # JS bridge accepts only String, Integer, Float, nil, boolean and JS::Object
  # as call arguments — an Array raises TypeError. JS::Bridge.to_js would
  # convert one, but by pushing each element across the boundary separately,
  # which is exactly the per-frame cost this avoids. Hex rather than raw bytes
  # because the bridge takes the string as a C string and a dark dot is a NUL.
  def levels_hex
    out = ""
    hex = HEX
    y = 1
    while y <= HEIGHT
      x = 1
      while x <= WIDTH
        out << hex[level_at(x, y)].to_s
        x += 1
      end
      y += 1
    end
    out
  end

  def level_at(x, y)
    v = (brightness(x, y) * 255.0).to_i
    return 0 if v < 0
    return 255 if 255 < v
    v
  end

  # The same values as an Array, for tests and for anything that would rather
  # not parse hex.
  def levels
    out = []
    y = 1
    while y <= HEIGHT
      x = 1
      while x <= WIDTH
        out << level_at(x, y)
        x += 1
      end
      y += 1
    end
    out
  end

  # Rendered as text, for the headless test and for anyone without a browser.
  def to_s
    lines = ""
    y = 1
    while y <= HEIGHT
      x = 1
      while x <= WIDTH
        lines << ((0.0 < brightness(x, y)) ? "#" : ".")
        x += 1
      end
      lines << "\n"
      y += 1
    end
    lines
  end
end
