# Headless check of the simulator core: the real driver from
# mrbgems/picoruby-is31fl3729 talking to two virtual chips through the virtual
# bus, so that the coordinate mapping can be verified without a browser.
#
#   bin/picoruby sim/test/panel_test.rb
#
# Run from the repository root.

$failures = 0
$checks = 0

def check(label)
  $checks += 1
  ok = yield
  if ok
    puts "  ok   #{label}"
  else
    puts "  FAIL #{label}"
    $failures += 1
  end
rescue => e
  puts "  FAIL #{label} (#{e.class}: #{e.message})"
  $failures += 1
end

# picoruby resolves a relative path through $LOAD_PATH, which bin/picoruby
# leaves empty, so point it at the working directory. lib/ is on there too, so
# that the board layer's own requires resolve exactly as they do on the device,
# where $LOAD_PATH is ["/lib"].
$LOAD_PATH = [".", "lib"]
# sim_panel.rb first: it defines the I2C and GPIO stand-ins and tolerates the
# driver's `require 'i2c'`. Then the real driver, then the board layer that
# will also be loaded from /lib on the device.
load "sim/sim_panel.rb"
# midibase and its MML front end are pure Ruby, which is what lets the real
# parser and router be tested here rather than only in a browser.
%w[
  mrbgems/picoruby-midibase/mrblib/midibase.rb
  mrbgems/picoruby-midibase/mrblib/router.rb
  mrbgems/picoruby-midibase/mrblib/parser.rb
  mrbgems/picoruby-midibase/mrblib/clock.rb
  mrbgems/picoruby-midibase/mrblib/session.rb
  mrbgems/picoruby-midibase/mrblib/voice_allocator.rb
  mrbgems/picoruby-midibase-mml/mrblib/clock.rb
  mrbgems/picoruby-midibase-mml/mrblib/parser.rb
  mrbgems/picoruby-midibase-mml/mrblib/sequence.rb
  mrbgems/picoruby-midibase-mml/mrblib/player.rb
].each { |f| load f }
load "mrbgems/picoruby-is31fl3729/mrblib/is31fl3729.rb"
load "lib/picorubykaigi01.rb"

# Router timestamps with Machine.uptime_us, which neither bin/picoruby nor the
# wasm build provides. Defined before sim_audio.rb so that its own stand-in,
# which needs a browser, is skipped.
unless Object.const_defined?(:Machine)
  module Machine
    def self.uptime_us
      0
    end
  end
end

# NoteLog lives here; the WebAudio parts of the file only touch JS inside their
# methods, so it loads without a browser.
load "sim/sim_audio.rb"


# The page boots the real board layer, so the test boots the same thing:
# Board.boot raises SDB, builds LedMatrix on the virtual bus and the buttons on
# the GPIO stand-in.
# Records what a sink would have been asked to play.
class RecordingSink
  attr_reader :events
  def initialize
    @events = []
  end
  def handle(event, source: :mml, priority: 0, timestamp_us: nil, **_c)
    handle_midi(event, source, priority, timestamp_us)
  end
  def handle_midi(event, _source, _priority, _timestamp_us)
    @events << event
    true
  end
end

def new_board(global_current: 0x20)
  GPIO.reset
  panel = Panel.new
  board = Board.boot(i2c: panel.i2c, speaker_backend: RecordingSink.new,
                     global_current: global_current)
  $board = board
  m = board.matrix
  [panel, m.top, m.bottom, m, board]
end

def light(m, x, y, pwm = 0xFF)
  m.set(x, y, pwm)
  m.show
end

puts "1. every one of the 256 pixels lights alone"
panel, top, bottom, m, board = new_board
wrong = nil
y = 1
while y <= 16 && wrong.nil?
  x = 1
  while x <= 16 && wrong.nil?
    m.clear; m.show
    light(m, x, y)
    ly = 1
    while ly <= 16 && wrong.nil?
      lx = 1
      while lx <= 16 && wrong.nil?
        lit = 0.0 < panel.brightness(lx, ly)
        want = (lx == x && ly == y)
        wrong = [x, y, lx, ly, lit, want] if lit != want
        lx += 1
      end
      ly += 1
    end
    x += 1
  end
  y += 1
end
check("all 256 pixels map one to one") { wrong.nil? }
puts "     #{wrong.inspect}" if wrong

puts "2. the bottom half really is column reversed"
panel, top, bottom, m, board = new_board
bottom.set_dot(1, 16, 0xFF) # CS16 on the second chip
bottom.flush
check("chip CS16 shows at x = 1, y = 9") { 0.0 < panel.brightness(1, 9) }
check("and nowhere else on that row")    { panel.brightness(16, 9) == 0.0 }

panel, top, bottom, m, board = new_board
top.set_dot(1, 16, 0xFF) # CS16 on the first chip
top.flush
check("chip CS16 shows at x = 16, y = 1 on the top half") { 0.0 < panel.brightness(16, 1) }

puts "3. the chip boundary sits between rows 8 and 9"
panel, top, bottom, m, board = new_board
top.set_dot(8, 5, 0xFF); top.flush
check("row 8 comes from the top chip")    { 0.0 < panel.brightness(5, 8) }
check("row 9 is still dark")              { panel.brightness(5, 9) == 0.0 }
bottom.set_dot(1, Panel::WIDTH + 1 - 5, 0xFF); bottom.flush
check("row 9 comes from the bottom chip") { 0.0 < panel.brightness(5, 9) }

puts "4. a chip that is only reset stays dark"
panel = Panel.new
led = IS31FL3729.new(i2c: panel.i2c, address: Panel::TOP_ADDRESS)
led.reset
led.configure
led.set_dot(1, 1, 0xFF)
led.flush
check("no global current, no scaling, no light") { panel.brightness(1, 1) == 0.0 }
led.global_current = 0x20
check("global current alone is not enough")      { panel.brightness(1, 1) == 0.0 }
led.scaling_all = 0xFF
check("with scaling too it lights")              { 0.0 < panel.brightness(1, 1) }

puts "5. software shutdown blanks the panel"
panel, top, bottom, m, board = new_board
top.fill(0xFF); top.flush
check("lit before shutdown") { 0.0 < panel.brightness(1, 1) }
top.shutdown
check("dark after shutdown") { panel.brightness(1, 1) == 0.0 }
top.resume
check("lit again after resume") { 0.0 < panel.brightness(1, 1) }

puts "6. an L drawn across the chip boundary looks like an L"
panel, top, bottom, m, board = new_board
# Vertical stroke down column 3 from row 2 to row 14, then along row 14.
y = 2
while y <= 14
  light(m, 3, y)
  y += 1
end
x = 4
while x <= 10
  light(m, x, 14)
  x += 1
end
expected =
  "................\n" \
  "..#.............\n" \
  "..#.............\n" \
  "..#.............\n" \
  "..#.............\n" \
  "..#.............\n" \
  "..#.............\n" \
  "..#.............\n" \
  "..#.............\n" \
  "..#.............\n" \
  "..#.............\n" \
  "..#.............\n" \
  "..#.............\n" \
  "..########......\n" \
  "................\n" \
  "................\n"
check("the picture matches, spanning both chips") { panel.to_s == expected }
unless panel.to_s == expected
  puts "--- got ---"
  puts panel.to_s
end

puts "7. levels() hands over 256 values"
panel, top, bottom, m, board = new_board
light(m, 1, 1)
levels = panel.levels
check("256 entries")            { levels.size == 256 }
check("first one is lit")       { 0 < levels[0].to_i }
check("second one is not")      { levels[1].to_i == 0 }
check("levels_hex is 512 chars")  { panel.levels_hex.bytesize == 512 }
check("levels_hex agrees with levels") do
  ls = panel.levels
  hex = panel.levels_hex
  ok = true
  i = 0
  while i < 256
    ok = false if hex[i * 2, 2].to_s != Panel::HEX[ls[i].to_i].to_s
    i += 1
  end
  ok
end
check("brightness follows GCC") do
  p2, _t2, _b2, m2, _bd2 = new_board(global_current: 0x40)
  m2.set(1, 1); m2.show
  levels[0].to_i < p2.levels[0].to_i
end

puts "8. SDB gates the whole panel"
panel, top, bottom, m, board = new_board
m.fill(0xFF); m.show
check("lit while SDB is high") { 0.0 < panel.brightness(1, 1) }
GPIO.write_at(Panel::SDB_PIN, 0)
check("dark while SDB is low")  { panel.brightness(1, 1) == 0.0 }
GPIO.write_at(Panel::SDB_PIN, 1)
check("lit again")              { 0.0 < panel.brightness(1, 1) }

puts "9. buttons are driven by edges, not by polling"
_p, _t, _b, _m, board = new_board
buttons = board.buttons
check("nothing pressed at rest") { !buttons.any? }

GPIO.press(17) # up
check("a press is seen immediately") { buttons.pressed?(:up) }
check("and only that one")           { !buttons.pressed?(:down) }
check("and it is queued")            { buttons.presses_waiting == 1 }
check("taking it gives the name")    { buttons.take_press == :up }
check("and only once")               { buttons.take_press.nil? }
check("still held")                  { buttons.pressed?(:up) }

GPIO.release(17)
check("released")            { !buttons.pressed?(:up) }
check("no phantom press")    { buttons.take_press.nil? }

# The case that made quick taps disappear: with polling, a click that started
# and finished between two samples was never seen at all.
GPIO.press(17)
GPIO.release(17)
check("a click with no poll in the middle is still queued") { buttons.take_press == :up }
check("and the level is back up")                           { !buttons.pressed?(:up) }

# Several presses in a row all survive, in order.
GPIO.press(19); GPIO.release(19)
GPIO.press(20); GPIO.release(20)
GPIO.press(19); GPIO.release(19)
taken = []
buttons.each_press { |name| taken << name }
check("every press is delivered, in order") { taken == [:left, :right, :left] }
check("the queue is empty afterwards")      { buttons.presses_waiting == 0 }

GPIO.press(17)
GPIO.press(21) # a
check("two at once") { buttons.pressed?(:up) && buttons.pressed?(:a) }
check("pressed lists both") do
  names = buttons.pressed
  names.size == 2 && names.include?(:up) && names.include?(:a)
end
GPIO.release(17)
GPIO.release(21)
check("released")            { !buttons.any? }
buttons.clear_presses

check("every name maps to a pin") do
  ok = true
  names = Buttons::NAMES
  i = 0
  while i < names.size
    GPIO.reset
    GPIO.write_at(Panel::SDB_PIN, 1)
    b = Buttons.new
    GPIO.press(Board::BUTTON_PINS[i][1])
    ok = false unless b.take_press == names[i] && b.pressed == [names[i]]
    i += 1
  end
  ok
end

puts "9-3. the status LED is active high on GPIO16"
_p, _t, _b, _m, board = new_board
led = board.status_led
check("starts off")            { !led.on? && GPIO.read_at(Board::STATUS_LED_PIN) == 0 }
led.on
check("on drives the pin high"){ led.on? && GPIO.read_at(Board::STATUS_LED_PIN) == 1 }
led.toggle
check("toggle turns it off")   { !led.on? && GPIO.read_at(Board::STATUS_LED_PIN) == 0 }
led.toggle
check("and back on")           { led.on? }
led.write(0)
check("write(0) is off")       { !led.on? }
led.write(1)
check("write(1) is on")        { led.on? }

puts "10. MML turns into the MIDI events the synth expects"
seq = MIDIBASE::MML::Sequence.new(["t120 o4 l4 cde"])
notes = []
i = 0
while i < 40
  pair = seq.next_event
  break unless pair
  event = pair[1]
  notes << event[2] if event[0] == :note_on && 0 < event[3].to_i
  i += 1
end
check("the three notes come out as C4 D4 E4") { notes[0, 3] == [60, 62, 64] }

puts "11. Speaker routes to its sink and drives the amplifier"
GPIO.reset
sink = RecordingSink.new
spk = Speaker.new(sink: sink)
check("amplifier starts muted") { GPIO.read_at(Board::AMP_SD_PIN) == 0 }

spk.note_on(60, velocity: 90)
check("note_on reaches the sink")  { sink.events[-1] == [:note_on, 0, 60, 90] }
check("and unmutes the amplifier") { GPIO.read_at(Board::AMP_SD_PIN) == 1 }

spk.note_off(60)
check("note_off reaches the sink") { sink.events[-1] == [:note_off, 0, 60] }

spk.stop
check("stop sends all notes off") { sink.events[-1] == [:control_change, 0, 123, 0] }
check("and mutes again")          { GPIO.read_at(Board::AMP_SD_PIN) == 0 }

puts "12. the note log reads events back as names"
log = NoteLog.new
log.handle([:note_on, 0, 60, 100], timestamp_us: 0)
log.handle([:note_on, 0, 72, 0], timestamp_us: 500_000)   # velocity 0 is a note off
log.handle([:note_off, 0, 60], timestamp_us: 1_000_000)
lines = log.entries
check("three entries")        { lines.size == 3 }
check("middle C is named C4") { lines[0].include?("C4") && lines[0].include?("on") }
check("zero velocity is off") { lines[1].include?("off") && lines[1].include?("C5") }
check("elapsed time is shown"){ lines[2].include?("1000ms") }

puts
puts "#{$checks - $failures}/#{$checks} checks passed"
if 0 < $failures
  puts "FAILED"
else
  puts "OK"
end
