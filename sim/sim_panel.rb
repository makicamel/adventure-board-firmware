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

# The picorubykaigi01 panel: 16x16 from two chips.
#
# Rows 1..8 are U10 at 0x34 and rows 9..16 are U11 at 0x35. U11 has its columns
# wired in reverse, so its CS index is 17 - x. Both facts come from the r1
# netlist; see dev-docs/led-matrix-gem/hardware.md section 4.
class Panel
  WIDTH  = 16
  HEIGHT = 16

  TOP_ADDRESS    = 0x34
  BOTTOM_ADDRESS = 0x35

  attr_reader :i2c, :top, :bottom

  def initialize
    @i2c = I2C.new
    @top = VirtualIS31FL3729.new
    @bottom = VirtualIS31FL3729.new
    @i2c.attach(TOP_ADDRESS, @top)
    @i2c.attach(BOTTOM_ADDRESS, @bottom)
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
    chip, sw, cs = locate(x, y)
    chip.brightness_at(sw, cs)
  end

  # The whole panel as 256 values of 0..255, row major from (1, 1). This is the
  # one thing handed to the renderer, so a frame costs a single JS call.
  def levels
    out = []
    y = 1
    while y <= HEIGHT
      x = 1
      while x <= WIDTH
        out << (brightness(x, y) * 255.0).to_i
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

# The 16x16 panel as the board layer will eventually expose it. Kept small on
# purpose: this doubles as a sketch of the API that /lib/picorubykaigi01.rb is
# going to have, so the samples written here should carry over.
class LedMatrix
  WIDTH  = Panel::WIDTH
  HEIGHT = Panel::HEIGHT

  attr_reader :panel

  def initialize(global_current: 0x20)
    @panel = Panel.new
    @top = IS31FL3729.new(i2c: @panel.i2c, address: Panel::TOP_ADDRESS)
    @bottom = IS31FL3729.new(i2c: @panel.i2c, address: Panel::BOTTOM_ADDRESS)
    @global_current = global_current
    @top.setup(global_current: global_current)
    @bottom.setup(global_current: global_current)
  end

  # x and y are 1-based. The driver is handed the row and column of whichever
  # chip owns that pixel, including the reversed columns of the bottom one.
  def set(x, y, pwm = 0xFF)
    return self if x < 1 || WIDTH < x || y < 1 || HEIGHT < y
    if y <= 8
      @top.set_dot(y, x, pwm)
    else
      @bottom.set_dot(y - 8, WIDTH + 1 - x, pwm)
    end
    self
  end

  def clear
    @top.clear
    @bottom.clear
    self
  end

  def fill(pwm = 0xFF)
    @top.fill(pwm)
    @bottom.fill(pwm)
    self
  end

  # Nothing reaches the chips until this runs, exactly as on hardware.
  def show
    @top.flush
    @bottom.flush
    self
  end

  def brightness=(value)
    @global_current = value
    @top.global_current = value
    @bottom.global_current = value
    value
  end

  def brightness
    @global_current
  end

  # For code that wants the chips directly.
  def top
    @top
  end

  def bottom
    @bottom
  end
end
