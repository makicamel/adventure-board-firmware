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

  # --- drawing ------------------------------------------------------------
  #
  # Everything above works dot by dot with 8-bit brightness. What follows goes
  # through picoruby-vram, which is 1-bit only, so shapes and text are on or
  # off and `blit` decides how bright "on" is. The two are deliberately
  # separate: `set` for brightness, the VRAM for drawing.
  #
  # picoruby-shinonome carries the 16x16 JIS font, which is the whole reason
  # this panel is 16x16 rather than 12x12.
  begin
    include Shinonome::Drawable
  rescue NameError
    # No picoruby-shinonome in this build; only the shape API is available.
  end

  # Built on first use: a board without picoruby-vram can still light dots.
  def vram
    @vram ||= VRAM.new(w: WIDTH, h: HEIGHT, cols: 1, rows: HEIGHT / 8)
  end

  # What BDFFont::Drawable calls, and so what makes draw_shinonome work.
  def draw_bitmap(x:, y:, w:, h:, data:)
    vram.draw_bitmap(x: x, y: y, w: w, h: h, data: data)
    nil
  end

  def draw_text(text, x = 0, y = 0, font: "go16")
    draw_shinonome(font, x, y, text)
    self
  end

  def set_pixel(x, y, color = 1)
    vram.set_pixel(x, y, color)
    self
  end

  def draw_line(x0, y0, x1, y1, color = 1)
    vram.draw_line(x0, y0, x1, y1, color)
    self
  end

  def draw_rect(x, y, w, h, color = 1)
    vram.draw_rect(x, y, w, h, color)
    self
  end

  def clear_drawing
    vram.fill(0)
    self
  end

  # Copy the 1-bit buffer onto the dots. VRAM is 0-based and organised in pages
  # of eight rows, one byte per column, bit 0 at the top.
  #
  # This is 256 assignments per frame and the one place worth rewriting in C if
  # it ever proves too slow; nothing else in the drawing path is per-pixel.
  def blit(on: 0xFF, off: 0x00)
    pages = vram.pages
    pi = 0
    while pi < pages.size
      page = pages[pi]
      row = page[1].to_i
      data = page[2].to_s
      x = 0
      while x < WIDTH
        byte = data.getbyte(x) || 0
        b = 0
        while b < 8
          set(x + 1, row * 8 + b + 1, ((byte >> b) & 1) == 1 ? on : off)
          b += 1
        end
        x += 1
      end
      pi += 1
    end
    self
  end
end

# The speaker.
#
# The board's signal path is PWM on GPIO10 into an RC filter and a PAM8302A,
# driven by picoruby-psg. What is here is a layer above that: MML is turned
# into MIDI events by picoruby-midibase-mml and routed to whatever sink was
# handed in — PSG::Synth on the board, JS::WebAudio::Synth in the simulator.
# Both take the same events, so nothing below this line changes between them.
class Speaker
  # The amplifier's shutdown pin. Held low when nothing is playing: leaving the
  # PAM8302A enabled in silence puts its noise floor on the speaker.
  attr_reader :router, :sink

  def initialize(sink:, amp_sd_pin: Board::AMP_SD_PIN)
    @sink = sink
    @amp = amp_sd_pin ? GPIO.new(amp_sd_pin, GPIO::OUT) : nil
    @router = MIDIBASE::Router.new
    @router.connect(:mml, sink)
    @player = nil
    mute
  end

  # `mml` is one track as a String, or several as an Array.
  #
  #   speaker.play_mml("t120 o4 l8 cdefgab>c")
  def play_mml(mml, loop: false)
    stop
    unmute
    tracks = mml.is_a?(Array) ? mml : [mml]
    sequence = MIDIBASE::MML::Sequence.new(tracks, loop: loop)
    @player = MIDIBASE::MML::Player.new(
      sequence,
      clock: MIDIBASE::MML::InternalClock.new,
      output: @router.output(:mml)
    )
    @player.start
    self
  end

  def playing?
    player = @player
    !player.nil? && !player.stopped?
  end

  def stop
    player = @player
    player.stop if player
    @player = nil
    all_notes_off
    mute
    self
  end

  # A single note, for when a melody would be overkill. 60 is middle C.
  def note_on(note, velocity: 100, channel: 0)
    unmute
    @router.emit(:mml, [:note_on, channel, note, velocity])
    self
  end

  def note_off(note, channel: 0)
    @router.emit(:mml, [:note_off, channel, note])
    self
  end

  def all_notes_off(channel: 0)
    @router.emit(:mml, [:control_change, channel, 123, 0])
    self
  end

  def unmute
    amp = @amp
    amp.write(1) if amp
    self
  end

  def mute
    amp = @amp
    amp.write(0) if amp
    self
  end
end

# The six buttons.
#
# Each pin has a 10k pull-up on the board, so a pressed button reads low. The
# pins are consecutive, which is why they are kept in one array and swept in
# order rather than being six separate objects to poll.
class Buttons
  NAMES = [:up, :down, :left, :right, :a, :b]

  # Auto-repeat, counted in `update` calls rather than milliseconds so that no
  # clock is needed. With a 60ms loop the defaults give one step, a pause of
  # about a third of a second, then a step every ~120ms — the way a key
  # repeats. Without this, holding a direction moves as fast as the loop runs,
  # which is several cells before a finger comes off the button.
  DEFAULT_REPEAT_DELAY = 6
  DEFAULT_REPEAT_INTERVAL = 2

  def initialize(pins: Board::BUTTON_PINS,
                 repeat_delay: DEFAULT_REPEAT_DELAY,
                 repeat_interval: DEFAULT_REPEAT_INTERVAL)
    @names = []
    @gpios = []
    @held = []
    i = 0
    while i < pins.size
      @names << pins[i][0]
      @gpios << GPIO.new(pins[i][1], GPIO::IN | GPIO::PULL_UP)
      @held << 0
      i += 1
    end
    @raw = 0
    @stable = 0
    @previous = 0
    @repeated = 0
    @repeat_delay = repeat_delay
    @repeat_interval = (repeat_interval < 1) ? 1 : repeat_interval
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
    update_repeat
    self
  end

  # Fires once when a button goes down, then again on a repeat tick. This is
  # what a cursor should move on.
  def repeat?(name)
    index = index_of(name)
    return false if index < 0
    (@repeated & (1 << index)) != 0
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

  # How many consecutive samples each button has been down for, and which of
  # them should act this time.
  def update_repeat
    repeated = 0
    held = @held
    stable = @stable
    delay = @repeat_delay
    interval = @repeat_interval
    i = 0
    size = held.size
    while i < size
      mask = 1 << i
      if (stable & mask) == 0
        held[i] = 0
      else
        n = held[i] + 1
        held[i] = n
        if n == 1
          repeated |= mask
        elsif delay < n && (n - delay - 1) % interval == 0
          repeated |= mask
        end
      end
      i += 1
    end
    @repeated = repeated
    nil
  end

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
