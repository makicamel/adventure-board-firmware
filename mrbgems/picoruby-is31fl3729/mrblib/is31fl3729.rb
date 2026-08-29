require 'i2c'

# Driver for the Lumissil IS31FL3729 matrix LED driver.
#
# The chip sinks up to 16 columns (CS) across up to 9 rows (SW) with 8-bit PWM
# per dot and runs the scan itself, so the host only writes a frame. One
# instance owns one chip; a panel built from several chips composes instances
# rather than being handled here, because the chip has no SYNC pin and nothing
# is shared between two of them but the bus.
#
# The register layout is what makes this cheap: the PWM byte of a dot lives at
# `(sw - 1) * 0x10 + cs`, so a row is 16 contiguous registers and the rows
# follow one another without a gap from 0x01. Together with the chip's address
# auto-increment, a whole frame is a single I2C transaction.
class IS31FL3729
  # I2C address, selected by what the AD pin is tied to (datasheet Table 1).
  ADDRESS_GND = 0x34
  ADDRESS_SCL = 0x35
  ADDRESS_SDA = 0x36
  ADDRESS_VCC = 0x37

  # Registers (datasheet Table 5).
  PWM_BASE        = 0x01  # 0x01..0x8F, one byte per dot
  SCALING_BASE    = 0x90  # 0x90..0x9F, one byte per CS
  CONFIGURATION   = 0xA0
  GLOBAL_CURRENT  = 0xA1
  PULL_RESISTOR   = 0xB0
  SPREAD_SPECTRUM = 0xB1
  PWM_FREQUENCY   = 0xB2
  OPEN_SHORT_BASE = 0xB3  # 0xB3..0xC4
  RESET           = 0xCF

  # The reset register reacts to this one value only.
  RESET_VALUE = 0xAE

  # Configuration register (0xA0) fields.
  SSD = 0x01  # 1 = normal operation. POR is 0, so it has to be set explicitly.
  LGC = 0x08  # 0 = VIH 1.4V / VIL 0.4V, 1 = VIH 2.4V / VIL 0.6V

  # Open/short detection, D2:D1 of the configuration register. Detection runs
  # once per 00 -> non-zero transition.
  OSDE_DISABLE = 0x00
  OSDE_OPEN    = 0x02
  OSDE_SHORT   = 0x04

  # Global current control (0xA1) has 65 steps; the chip clamps anything above.
  GLOBAL_CURRENT_MAX = 0x40

  ROW_STRIDE      = 0x10  # PWM registers per row. CS16 occupies the 16th.
  SCALING_COUNT   = 16    # 0x90..0x9F, one per CS, independent of the row count
  OPEN_SHORT_SIZE = 18    # 0xB3..0xC4

  MIN_ROWS = 2
  MAX_ROWS = 9

  attr_reader :address, :rows, :columns

  # Nothing is written here: the caller decides when the chip may be talked to.
  # On a board where SDB is filtered, the pin has to be high and settled first.
  def initialize(i2c:, address: ADDRESS_GND, rows: 8, logic_high: true)
    if rows < MIN_ROWS || MAX_ROWS < rows
      raise ArgumentError, "rows must be #{MIN_ROWS}..#{MAX_ROWS}"
    end
    @i2c = i2c
    @address = address
    @rows = rows
    # SW9 doubles as CS16, so running all 9 rows is what costs the 16th column.
    @columns = (rows == MAX_ROWS) ? 15 : 16
    @logic_high = logic_high
    @buffer = "\x00" * (rows * ROW_STRIDE)
    @dirty_from = 0
    @dirty_to = @buffer.bytesize - 1
  end

  # Bring the chip up and leave it dark but ready.
  #
  # A reset alone is not enough to see anything: the power-on value of both the
  # global current and the scaling registers is 0, which means no current at
  # all. Forgetting either is the usual reason a correct-looking driver stays
  # black.
  def setup(global_current:, scaling: 0xFF)
    reset
    configure
    self.global_current = global_current
    self.scaling_all = scaling
    clear
    flush
    self
  end

  def reset
    write_register(RESET, RESET_VALUE)
  end

  # SWS (D7:D4) counts down from 9 rows at 0b0000, so 8 rows is 0b0001.
  def configure(enabled: true, open_short: OSDE_DISABLE)
    value = ((MAX_ROWS - @rows) << 4) | open_short
    value |= LGC if @logic_high
    value |= SSD if enabled
    write_register(CONFIGURATION, value)
  end

  # Software shutdown. The frame buffer in the chip survives it.
  def shutdown
    configure(enabled: false)
  end

  def resume
    configure(enabled: true)
  end

  def global_current=(value)
    value = 0 if value < 0
    value = GLOBAL_CURRENT_MAX if GLOBAL_CURRENT_MAX < value
    write_register(GLOBAL_CURRENT, value)
    value
  end

  # The scaling block is 16 registers wide whatever the row count, so all of it
  # is written even when CS16 is not in use.
  def scaling_all=(value)
    write_register(SCALING_BASE, (value & 0xFF).chr * SCALING_COUNT)
    value
  end

  def set_scaling(cs, value)
    check_cs(cs)
    write_register(SCALING_BASE + cs - 1, value & 0xFF)
  end

  # Register address of one dot (datasheet Figure 9).
  def register_of(sw, cs)
    (sw - 1) * ROW_STRIDE + cs
  end

  def set_dot(sw, cs, pwm)
    check_sw(sw)
    check_cs(cs)
    offset = register_of(sw, cs) - PWM_BASE
    @buffer.setbyte(offset, pwm & 0xFF)
    mark_dirty(offset)
    pwm
  end

  def dot(sw, cs)
    check_sw(sw)
    check_cs(cs)
    @buffer.getbyte(register_of(sw, cs) - PWM_BASE) || 0
  end

  def fill(pwm)
    @buffer = (pwm & 0xFF).chr * (@rows * ROW_STRIDE)
    @dirty_from = 0
    @dirty_to = @buffer.bytesize - 1
    nil
  end

  def clear
    fill(0)
  end

  # A copy, so that a caller cannot desynchronise the dirty range by mutating
  # the buffer behind our back.
  def frame
    @buffer.dup
  end

  # Replace the whole buffer at once. This is the path a display layer uses:
  # it renders into a string of its own and hands the finished frame over,
  # which keeps the per-pixel work out of this class.
  def frame=(bytes)
    size = @rows * ROW_STRIDE
    if bytes.bytesize != size
      raise ArgumentError, "frame must be #{size} bytes, got #{bytes.bytesize}"
    end
    @buffer = bytes.dup
    @dirty_from = 0
    @dirty_to = size - 1
    bytes
  end

  def dirty?
    0 <= @dirty_from
  end

  # Push the changed part of the buffer. The chip auto-increments its address
  # pointer, so any run of registers goes out as one transaction; a full frame
  # is one write of 1 + rows * 16 bytes.
  def flush
    from = @dirty_from
    return false if from < 0
    to = @dirty_to
    write_register(PWM_BASE + from, @buffer[from..to].to_s)
    @dirty_from = -1
    @dirty_to = -1
    true
  end

  # Raw contents of the open/short registers. Running a detection also needs
  # the current and the pull resistors set up first; that sequence belongs to
  # a board-level self test, not here.
  def read_open_short
    @i2c.read(@address, OPEN_SHORT_SIZE, OPEN_SHORT_BASE)
  end

  private

  def write_register(register, value)
    @i2c.write(@address, register, value)
    nil
  end

  def mark_dirty(offset)
    if @dirty_from < 0 || offset < @dirty_from
      @dirty_from = offset
    end
    if @dirty_to < offset
      @dirty_to = offset
    end
    nil
  end

  def check_sw(sw)
    if sw < 1 || @rows < sw
      raise RangeError, "sw must be 1..#{@rows}, got #{sw}"
    end
    nil
  end

  def check_cs(cs)
    if cs < 1 || @columns < cs
      raise RangeError, "cs must be 1..#{@columns}, got #{cs}"
    end
    nil
  end
end
