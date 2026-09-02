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
