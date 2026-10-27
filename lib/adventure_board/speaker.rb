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

  # `pan` is where a channel sits until a piece moves it (MML `p`), as a MIDI
  # pan: 0 left, 64 centre, 127 right. Whoever builds the speaker knows what
  # is wired to it -- this board has one speaker, on the left output.
  def initialize(sink:, amp_sd_pin: Board::AMP_SD_PIN, pan: 64)
    @sink = sink
    @amp = amp_sd_pin ? GPIO.new(amp_sd_pin, GPIO::OUT) : nil
    @router = MIDIBASE::Router.new
    @router.connect(:mml, sink)
    @player = nil
    @task = nil
    @pan = pan
    @channels = 0   # how many channels anything has been sent on so far
    use_channels(1)
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
      router.emit(:mml, [:control_change, ch, 10, @pan])  # pan: where the speaker is
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
    use_channels(tracks.size)   # track n plays on channel n
    sequence = MIDIBASE::MML::Sequence.new(tracks, loop: loop)
    @player = MIDIBASE::MML::Player.new(
      sequence,
      clock: MIDIBASE::MML::InternalClock.new,
      output: @router.output(:mml)
    )
    # Not Player#start: it makes a Task nobody closes, and a Task that has
    # finished stays in the heap until it is closed, so a program playing
    # short pieces over and over runs out of it. This one is closed when the
    # next piece starts or the speaker stops (halt), so at most one is left.
    player = @player
    @task = Task.new(name: "Speaker") { player.run }
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

  # Counts the channels in use, and puts each new one where the speaker is.
  # A sound generator starts every channel at the centre, so there is
  # nothing to send for that.
  private def use_channels(count)
    ch = @channels
    while ch < count
      @router.emit(:mml, [:control_change, ch, 10, @pan]) unless @pan == 64
      ch += 1
    end
    @channels = count if @channels < count
    self
  end

  # Silence whatever is sounding, leaving the amplifier as it is.
  private def halt
    player = @player
    player.stop if player
    @player = nil
    task = @task
    task.close if task
    @task = nil
    ch = 0
    while ch < @channels
      all_notes_off(channel: ch)
      ch += 1
    end
    self
  end

  # A single note, for when a melody would be overkill. 60 is middle C.
  def note_on(note, velocity: 100, channel: 0)
    use_channels(channel + 1)
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
