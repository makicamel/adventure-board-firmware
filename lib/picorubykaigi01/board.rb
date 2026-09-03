# The board itself: which peripheral is on which pin, and how to bring them up.
#
# Everything a program touches hangs off one Board instance. `Board.boot`
# builds this board's own peripherals; the simulator hands in stand-ins
# instead, and everything below that point is the same either way.
#
# A peripheral is built the first time it is asked for, so a program that
# never touches the LED matrix never opens the drivers and never pulls SDB up.
# The classes themselves are required by the program, not from in here: what a
# sample loads is part of what it teaches, and on this device it is not free
# either. See dev-docs/device-bringup/require-memory.md.

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

  # Brings the board up. Nothing touches hardware yet; the peripherals below
  # build themselves the first time they are asked for.
  def self.boot(i2c: nil, speaker_backend: nil, global_current: 0x20)
    new(i2c: i2c, speaker_backend: speaker_backend,
        global_current: global_current)
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

  def initialize(i2c: nil, speaker_backend: nil, global_current: 0x20)
    @given_i2c = i2c
    @given_speaker_backend = speaker_backend
    @global_current = global_current
  end

  # --- the peripherals ------------------------------------------------------

  # I2C0, the bus the two LED drivers sit on.
  def i2c
    @i2c ||= @given_i2c || self.class.default_i2c
  end

  # SDB carries 0.2uF, so it needs the settle time before anything is said to
  # the drivers. Raised here rather than at boot, so a program that never uses
  # the matrix leaves the drivers shut down.
  def sdb
    @sdb ||= begin
      pin = GPIO.new(LED_SDB_PIN, GPIO::OUT)
      pin.write(1)
      self.class.settle
      pin
    end
  end

  def matrix
    @matrix ||= begin
      sdb
      LedMatrix.new(i2c: i2c, global_current: @global_current)
    end
  end

  def buttons
    @buttons ||= begin
      self.class.start_irq
      Buttons.new
    end
  end

  # nil on a build with no sound generator, so this remembers that it tried
  # rather than asking again on every call.
  def speaker
    unless @speaker_built
      @speaker_built = true
      backend = @given_speaker_backend || self.class.default_speaker_backend
      if backend
          @speaker = Speaker.new(sink: backend)
      end
    end
    @speaker
  end

  def status_led
    @status_led ||= begin
      StatusLed.new
    end
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

  # Only touches what was actually brought up.
  def shutdown
    @speaker.stop if @speaker
    if @sdb
      self.class.settle
      @sdb.write(0)
    end
    nil
  end
end
