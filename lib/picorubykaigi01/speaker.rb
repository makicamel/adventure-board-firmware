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
    @channels = 1   # how many channels anything has been sent on so far
    mute
  end

  # Back to how the speaker starts out: nothing sounding, every channel at
  # its defaults. MML's `v` and `@` are a volume controller and a program
  # change, and the sound generator remembers them per channel. It outlives
  # the program that sent them -- `$board` stays around between programs --
  # so a piece that does not set them itself plays with whatever the last
  # one left behind. A program that makes sound starts with this.
  #
  #   speaker.reset
  def reset
    halt
    router = @router
    ch = 0
    while ch < @channels
      router.emit(:mml, [:program_change, ch, 0])
      router.emit(:mml, [:control_change, ch, 7, 127])    # volume
      router.emit(:mml, [:control_change, ch, 11, 127])   # expression
      router.emit(:mml, [:control_change, ch, 10, 64])    # pan: centre
      router.emit(:mml, [:control_change, ch, 1, 0])      # vibrato depth
      router.emit(:mml, [:control_change, ch, 64, 0])     # sustain
      router.emit(:mml, [:control_change, ch, 68, 0])     # legato
      router.emit(:mml, [:pitch_bend, ch, 8192])
      ch += 1
    end
    self
  end

  # `mml` is one track as a String, or several as an Array.
  #
  #   speaker.play_mml("t120 o4 l8 cdefgab>c")
  def play_mml(mml, loop: false)
    # Not `stop`: that mutes, and cycling the amplifier between two pieces
    # is a pop each time. It stays on from the first sound until `stop`.
    halt
    unmute
    tracks = mml.is_a?(Array) ? mml : [mml]
    @channels = tracks.size if @channels < tracks.size   # track n plays on channel n
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
    halt
    mute
    self
  end

  # Silence whatever is sounding, leaving the amplifier as it is.
  private def halt
    player = @player
    player.stop if player
    @player = nil
    ch = 0
    while ch < @channels
      all_notes_off(channel: ch)
      ch += 1
    end
    self
  end

  # A single note, for when a melody would be overkill. 60 is middle C.
  def note_on(note, velocity: 100, channel: 0)
    @channels = channel + 1 if @channels <= channel
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
