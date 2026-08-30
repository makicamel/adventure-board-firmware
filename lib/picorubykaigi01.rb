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
  # GROVE-B (J5). The same two pins are ADC2 and ADC3, so a program picks one
  # use or the other.
  GROVE_B_TX_PIN  = 28   # J5.2
  GROVE_B_RX_PIN  = 29   # J5.1

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

  attr_reader :i2c, :matrix, :buttons, :speaker, :status_led

  # Brings the board up. Called with no arguments it builds this board's own
  # peripherals; the simulator hands in stand-ins instead. Everything below
  # this method is the same either way.
  def self.boot(i2c: nil, speaker_backend: nil, global_current: 0x20)
    i2c ||= default_i2c
    speaker_backend ||= default_speaker_backend
    sdb = GPIO.new(LED_SDB_PIN, GPIO::OUT)
    sdb.write(1)
    settle
    new(
      sdb: sdb,
      i2c: i2c,
      matrix: LedMatrix.new(i2c: i2c, global_current: global_current),
      buttons: Buttons.new,
      speaker: speaker_backend && Speaker.new(sink: speaker_backend)
    ).tap { start_irq }
  end

  # I2C0, the bus the two LED drivers sit on.
  def self.default_i2c
    I2C.new(unit: :RP2040_I2C0,
            sda_pin: I2C0_SDA_PIN, scl_pin: I2C0_SCL_PIN,
            frequency: 400_000)
  end

  # PSG on the audio PWM pin, which feeds the RC filter and the PAM8302A.
  # GPIO11 is the same PWM slice and only reaches the breadboard header, so it
  # is handed over as the right channel and simply goes nowhere on the board.
  # nil on a build without picoruby-psg, and then there is no speaker.
  def self.default_speaker_backend
    PSG::Synth.new(
      PSG::Driver.new(:pwm, left: AUDIO_PWM_PIN, right: AUDIO_PWM_PIN_R),
      voice_count: 3
    ).start
  rescue NameError, NoMethodError
    nil
  end

  # Delivers interrupts from a dispatcher task, so nothing polls. PicoRuby
  # only; FemtoRuby has no IRQ.start yet and would need IRQ.process instead.
  def self.start_irq
    IRQ.start
  rescue NameError, NoMethodError
    nil
  end

  # sleep_ms is a picoruby Kernel method; a host that does not have it just
  # goes without the wait, which only matters against real silicon.
  def self.settle
    sleep_ms SDB_SETTLE_MS
  rescue NoMethodError, NameError
    nil
  end

  def initialize(sdb:, i2c:, matrix:, buttons:, speaker: nil, status_led: nil)
    @sdb = sdb
    @i2c = i2c
    @matrix = matrix
    @buttons = buttons
    @speaker = speaker
    @status_led = status_led
  end

  # GROVE-B as UART0, for talking to another board.
  #
  # Built on request rather than at boot: these pins are also ADC2 and ADC3,
  # and asking for the UART gives up the analogue side.
  #
  # ⚠ Two of these boards need a **crossed** cable. The function mux fixes the
  # UART roles by pin number — a pin whose number is a multiple of 4 can only
  # be TX and the next one only RX — so GPIO28 is TX and GPIO29 is RX on both
  # boards, and a straight cable would put TX against TX. Seeed sells one
  # (Grove - UART Crossover Cable 4Pin, SS100052406); a Grove-to-jumper pair
  # with the two signal wires swapped does the same job.
  def grove_uart(baudrate: 115200)
    @grove_uart ||= UART.new(
      unit: :RP2040_UART0,
      txd_pin: GROVE_B_TX_PIN,
      rxd_pin: GROVE_B_RX_PIN,
      baudrate: baudrate
    )
  end

  # GROVE-A as I2C1, for sensors and displays.
  def grove_i2c(frequency: 100_000)
    @grove_i2c ||= I2C.new(
      unit: :RP2040_I2C1,
      sda_pin: GROVE_A_SDA_PIN,
      scl_pin: GROVE_A_SCL_PIN,
      frequency: frequency
    )
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
# Edge interrupts rather than polling. A press is an event, so it cannot be
# missed however short the click is or however slowly the main loop runs — the
# level alone would lose a tap that started and finished between two polls.
# picoruby-irq debounces in the gem, so there is nothing to filter here.
#
# Presses queue up and are taken one at a time; the level is there separately
# for anything that should act while a button is held. Auto-repeat is not here
# on purpose: a loop that wants it can count its own ticks against `pressed?`,
# and one that does not is not paying for it.
class Buttons
  NAMES = [:up, :down, :left, :right, :a, :b]

  # Milliseconds, handled inside picoruby-irq.
  DEFAULT_DEBOUNCE_MS = 20

  # Presses beyond this are dropped rather than growing without bound; a loop
  # that far behind has bigger problems than a lost keystroke.
  QUEUE_LIMIT = 16

  def initialize(pins: Board::BUTTON_PINS, debounce: DEFAULT_DEBOUNCE_MS)
    @names = []
    @gpios = []
    @level = 0
    @queue = []
    i = 0
    while i < pins.size
      name = pins[i][0]
      gpio = GPIO.new(pins[i][1], GPIO::IN | GPIO::PULL_UP)
      @names << name
      @gpios << gpio
      watch(gpio, name, 1 << i, debounce)
      i += 1
    end
  end

  # Currently held down.
  def pressed?(name)
    (@level & mask_of(name)) != 0
  end

  def any?
    @level != 0
  end

  # The names currently held down.
  def pressed
    out = []
    names = @names
    i = 0
    while i < names.size
      out << names[i] if (@level & (1 << i)) != 0
      i += 1
    end
    out
  end

  # The oldest press not yet taken, or nil. Every press is delivered exactly
  # once, which is the whole point of queueing them.
  def take_press
    @queue.shift
  end

  def each_press
    while (name = @queue.shift)
      yield name
    end
    nil
  end

  def presses_waiting
    @queue.size
  end

  def clear_presses
    @queue = []
    nil
  end

  private

  # A method, not the body of the loop above: `while` opens no scope, so a
  # block written inside one closes over the shared variables and every button
  # would end up reporting the last one.
  def watch(gpio, name, mask, debounce)
    gpio.irq(GPIO::EDGE_FALL | GPIO::EDGE_RISE, debounce: debounce) do |_peripheral, event_type|
      if event_type == GPIO::EDGE_RISE
        @level &= ~mask
      else
        @level |= mask
        push(name)
      end
    end
    nil
  end

  def push(name)
    queue = @queue
    queue << name
    queue.shift while QUEUE_LIMIT < queue.size
    nil
  end

  def mask_of(name)
    names = @names
    i = 0
    while i < names.size
      return 1 << i if names[i] == name
      i += 1
    end
    0
  end
end

# --- what a program calls ----------------------------------------------------
#
# `$board` is set by whoever brought the board up: /etc/init.d on the device,
# the page in the simulator. A program never has to know how the peripherals
# were built, and the same source runs in both places.
#
# These are ordinary top-level methods, so they are private methods on Object
# and are reachable from anywhere, including inside a Task.

def board
  $board ||= Board.boot
end

def matrix
  board.matrix
end

def buttons
  board.buttons
end

def speaker
  board.speaker
end
