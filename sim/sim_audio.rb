# Audio side of the simulator.
#
# The chain the board will run is
#
#   MML text -> MIDIBASE::MML::Sequence/Player -> MIDIBASE::Router -> PSG
#
# and everything in it up to the last arrow is pure Ruby, so it runs here
# unchanged. Only the sound generator is swapped: PSG is a C extension, so the
# browser uses JS::WebAudio::Synth, which takes the same MIDIBASE events.
require 'js'

# MIDIBASE::Router timestamps events with Machine.uptime_us, and picoruby-machine
# is not in the wasm build (its gembox is `core`, which build_config/picoruby-wasm.rb
# does not pull in). performance.now() is the same clock in spirit.
unless Object.const_defined?(:Machine)
  module Machine
    def self.uptime_us
      (JS.global[:performance].now.to_f * 1000.0).to_i
    end
  end
end

# A MIDIBASE sink that records what was played.
#
# Sound cannot be checked from a headless browser, so the log is what makes
# audio verifiable at all — and it is genuinely useful when writing a melody.
class NoteLog
  NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
  LIMIT = 64

  def initialize
    @entries = []
    @started_us = nil
  end

  def entries
    @entries
  end

  def clear
    @entries = []
    @started_us = nil
    nil
  end

  def self.note_name(note)
    return "?" if note.nil?
    "#{NAMES[note % 12]}#{(note / 12) - 1}"
  end

  def handle(event, source: :mml, priority: 0, timestamp_us: nil, **_context)
    handle_midi(event, source, priority, timestamp_us)
  end

  def handle_midi(event, _source, _priority, timestamp_us)
    now = timestamp_us || Machine.uptime_us
    @started_us ||= now
    ms = (now - @started_us) / 1000
    case event[0]
    when :note_on
      # A note_on with zero velocity is a note_off by another name.
      if event[3].to_i == 0
        record(ms, "off", event[2])
      else
        record(ms, "on", event[2], event[3])
      end
    when :note_off
      record(ms, "off", event[2])
    end
    true
  end

  # "  120ms on  C4 v100"
  def to_s
    out = ""
    list = @entries
    i = 0
    while i < list.size
      out << list[i] << "\n"
      i += 1
    end
    out
  end

  private

  def record(ms, kind, note, velocity = nil)
    line = "#{ms.to_s.rjust(6)}ms  #{kind.ljust(3)} #{self.class.note_name(note).ljust(4)}"
    line << " v#{velocity}" if velocity
    @entries << line
    @entries.shift while LIMIT < @entries.size
    nil
  end
end

# The sink the board's Speaker is built with, so that enabling audio later does
# not mean rebuilding the board. Silent until a backend is attached, which is
# what lets a melody reach the note log with the sound switched off.
class SwitchableSink
  attr_accessor :backend

  def initialize(backend = nil)
    @backend = backend
  end

  def handle(event, source: :mml, priority: 0, timestamp_us: nil, **context)
    b = @backend
    return true unless b
    b.handle(event, source: source, priority: priority, timestamp_us: timestamp_us)
  end

  def handle_midi(event, source, priority, timestamp_us)
    b = @backend
    return true unless b
    b.handle_midi(event, source, priority, timestamp_us)
  end
end

# The browser's sound generator, standing in for PSG.
#
# The AudioContext starts suspended until a user gesture, which is why `resume`
# is a separate step wired to a button rather than something done at boot.
class WebAudioSpeaker
  attr_reader :synth

  def initialize(voice_count: 8)
    @synth = JS::WebAudio::Synth.new(voice_count: voice_count)
    @resumed = false
  end

  def resume
    # Not Synth#resume: that awaits the AudioContext promise, and the listener
    # this is called from has to be synchronous — the browser only lifts its
    # autoplay block for code running on the gesture's own stack, and a task
    # cannot suspend there ("Cannot use asynchronous Task API during
    # synchronous execution"). Resuming the context and letting the promise
    # settle on its own does the same job.
    @synth.context.resume
    @resumed = true
    self
  end

  def resumed?
    @resumed
  end

  # MIDIBASE sink interface: everything is forwarded to the synth.
  def handle(event, source: :mml, priority: 0, timestamp_us: nil, **context)
    @synth.handle(event, source: source, priority: priority, timestamp_us: timestamp_us)
  end

  def handle_midi(event, source, priority, timestamp_us)
    @synth.handle_midi(event, source, priority, timestamp_us)
  end
end
