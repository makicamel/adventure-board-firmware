# Board support for picorubykaigi01-board.
#
# This file is not a gem. It is meant to live on the device's filesystem as
# /lib/picorubykaigi01.rb and be picked up by `require 'picorubykaigi01'`, so
# that anyone can open it, read the pin numbers and change them. The register
# level work is in the picoruby-is31fl3729 gem; what is here is the part worth
# reading.
#
# Pin assignments come from
# ref/picorubykaigi01-board/docs/PicoBoard_BOM_pin_assignment_20260824.xlsx,
# which is machine-extracted from the board. docs/gpio_assignment.md is older
# and disagrees; do not use it.

class Board
  # --- pins ---------------------------------------------------------------
  I2C0_SDA_PIN    = 4    # LED drivers, through the 0 ohm R48
  I2C0_SCL_PIN    = 5    # LED drivers, through the 0 ohm R49
  LED_SDB_PIN     = 24   # both drivers, low = shutdown
  AUDIO_PWM_PIN   = 10   # PWM5A into the RC filter and the PAM8302A
  AUDIO_PWM_PIN_R = 11   # same slice, only on the breadboard header
  AMP_SD_PIN      = 23   # low = amplifier muted
  STATUS_LED_PIN  = 16   # green LED through R31
  GROVE_A_SDA_PIN = 6
  GROVE_A_SCL_PIN = 7

  # The six buttons, in GPIO order so they can be read in one sweep.
  BUTTON_PINS = [
    [:up,    17],
    [:down,  18],
    [:left,  19],
    [:right, 20],
    [:a,     21],
    [:b,     22]
  ]

  # SDB carries C37 + C38 = 0.2uF, so it takes far longer than the datasheet's
  # 10us to cross VIH. Wait before the first I2C transaction, and again before
  # pulling it low.
  SDB_SETTLE_MS = 1

  attr_reader :matrix, :buttons, :speaker, :status_led

  # The I2C bus and the speaker backend are handed in rather than built here:
  # on the board they are the real peripherals, in the simulator they are
  # stand-ins, and everything else in this file is the same either way.
  def self.boot(i2c:, speaker_backend: nil, global_current: 0x20)
    sdb = GPIO.new(LED_SDB_PIN, GPIO::OUT)
    sdb.write(1)
    settle
    new(
      sdb: sdb,
      matrix: LedMatrix.new(i2c: i2c, global_current: global_current),
      buttons: Buttons.new,
      speaker: speaker_backend && Speaker.new(backend: speaker_backend)
    )
  end

  # sleep_ms is a picoruby Kernel method; a host that does not have it just
  # goes without the wait, which only matters against real silicon.
  def self.settle
    sleep_ms SDB_SETTLE_MS
  rescue NoMethodError, NameError
    nil
  end

  def initialize(sdb:, matrix:, buttons:, speaker: nil, status_led: nil)
    @sdb = sdb
    @matrix = matrix
    @buttons = buttons
    @speaker = speaker
    @status_led = status_led
  end

  def shutdown
    @speaker.stop if @speaker
    self.class.settle
    @sdb.write(0)
    nil
  end
end

# The 16x16 matrix, built from two IS31FL3729.
#
# Rows 1..8 are the chip at 0x34 and rows 9..16 the one at 0x35, whose columns
# are wired in reverse. Both facts come from the r1 netlist; see
# dev-docs/led-matrix-gem/hardware.md section 4.
class LedMatrix
  WIDTH  = 16
  HEIGHT = 16

  TOP_ADDRESS    = 0x34
  BOTTOM_ADDRESS = 0x35

  attr_reader :top, :bottom

  def initialize(i2c:, global_current: 0x20)
    @top = IS31FL3729.new(i2c: i2c, address: TOP_ADDRESS)
    @bottom = IS31FL3729.new(i2c: i2c, address: BOTTOM_ADDRESS)
    @global_current = global_current
    @top.setup(global_current: global_current)
    @bottom.setup(global_current: global_current)
  end

  # x and y are 1-based.
  def set(x, y, pwm = 0xFF)
    return self if x < 1 || WIDTH < x || y < 1 || HEIGHT < y
    if y <= 8
      @top.set_dot(y, x, pwm)
    else
      # The bottom chip has its columns reversed.
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

  # Nothing reaches the chips until this runs.
  def show
    @top.flush
    @bottom.flush
    self
  end

  # 0..0x40. Start low: the matrix at full tilt draws 330mA, and the 5V rail is
  # not protected against going past what USB will give (see hardware.md 5-4).
  def brightness=(value)
    @global_current = value
    @top.global_current = value
    @bottom.global_current = value
    value
  end

  def brightness
    @global_current
  end
end

# The six buttons.
#
# Each pin has a 10k pull-up on the board, so a pressed button reads low. The
# pins are consecutive, which is why they are kept in one array and swept in
# order rather than being six separate objects to poll.
class Buttons
  NAMES = [:up, :down, :left, :right, :a, :b]

  def initialize(pins: Board::BUTTON_PINS)
    @names = []
    @gpios = []
    i = 0
    while i < pins.size
      @names << pins[i][0]
      @gpios << GPIO.new(pins[i][1], GPIO::IN | GPIO::PULL_UP)
      i += 1
    end
    @raw = 0
    @stable = 0
    @previous = 0
  end

  # Sample the pins. Two matching readings in a row are needed before a change
  # is believed, which is enough to keep a bouncing contact from firing twice.
  def update
    bits = 0
    gpios = @gpios
    i = 0
    size = gpios.size
    while i < size
      bits |= (1 << i) if gpios[i].read == 0 # active low
      i += 1
    end
    if bits == @raw
      @previous = @stable
      @stable = bits
    else
      @previous = @stable
      @raw = bits
    end
    self
  end

  def pressed?(name)
    index = index_of(name)
    return false if index < 0
    (@stable & (1 << index)) != 0
  end

  # True only on the sample where the button went down.
  def just_pressed?(name)
    index = index_of(name)
    return false if index < 0
    mask = 1 << index
    (@stable & mask) != 0 && (@previous & mask) == 0
  end

  def any?
    @stable != 0
  end

  # The names currently held down.
  def pressed
    out = []
    i = 0
    names = @names
    while i < names.size
      out << names[i] if (@stable & (1 << i)) != 0
      i += 1
    end
    out
  end

  private

  def index_of(name)
    names = @names
    i = 0
    while i < names.size
      return i if names[i] == name
      i += 1
    end
    -1
  end
end
