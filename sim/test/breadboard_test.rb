# Headless check of the breadboard (sim/sim_breadboard.rb) through the GPIO
# stand-in: code written for the board drives and reads the circuit.
#
#   bin/picoruby sim/test/breadboard_test.rb
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

$LOAD_PATH = ["."]
load "sim/sim_panel.rb"
load "sim/board_layout.rb"
load "sim/sim_circuit.rb"
load "sim/sim_breadboard.rb"
# The page's view, for the geometry that turns a click into a hole. Nothing
# in it that matters here touches the browser.
load "sim/sim_board_view.rb"

# A fresh breadboard and fresh pins for each case.
def fresh(text = "")
  GPIO.reset
  bb = Breadboard.new
  Breadboard.current = bb
  errors = bb.load_text(text)
  raise errors.join(", ") unless errors.empty?
  bb
end

def led_id(bb)
  i = 0
  while i < bb.parts.size
    return bb.parts[i][0] if bb.parts[i][1] == "led"
    i += 1
  end
  nil
end

puts "Holes"
check("a1 and j17 are holes")      { Breadboard.parse_hole("a1") == [0, 1] && Breadboard.parse_hole("j17") == [9, 17] }
check("k1, a18, a0, a01 are not")  { %w[k1 a18 a0 a01].all? { |h| Breadboard.parse_hole(h).nil? } }
check("J1-5 is J1's fifth socket") { Breadboard.parse_hole("J1-5") == [:j1, 5] && Breadboard.parse_hole("J1-21").nil? }
check("a3 and e3 are one strip")   { Breadboard.node_of("a3") == Breadboard.node_of("e3") }
check("e3 and f3 are not")         { Breadboard.node_of("e3") != Breadboard.node_of("f3") }
check("J1-5 is GPIO2, J1-2 GND")   { Breadboard.node_of("J1-5") == "GPIO2" && Breadboard.node_of("J1-2") == "GND" }

BLINK = <<~TEXT
  wire J1-5 a3
  resistor b3 b7
  led c7 c9
  wire J1-3 d9
TEXT

puts "Blinking an LED on GPIO2"
check("lit while the pin is high, dark while low") do
  bb = fresh(BLINK)
  led = GPIO.new(2, GPIO::OUT)
  dark_at_start = bb.led_current(led_id(bb)) < 1.0e-6
  led.write(1)
  lit = bb.led_current(led_id(bb))
  led.write(0)
  dark = bb.led_current(led_id(bb))
  puts "       #{(lit * 1000).round(2)} mA lit"
  dark_at_start && lit > 0.00055 && lit < 0.00070 && dark < 1.0e-6
end
check("brightness follows the current") do
  bb = fresh(BLINK)
  GPIO.new(2, GPIO::OUT).write(1)
  one = bb.led_brightness(led_id(bb))
  bb = fresh(BLINK.sub("resistor b3 b7", "resistor b3 b5\nresistor c5 b7"))
  GPIO.new(2, GPIO::OUT).write(1)
  two = bb.led_brightness(led_id(bb))
  puts "       one resistor #{one.round(3)}, two #{two.round(3)}"
  two / one > 0.48 && two / one < 0.65
end
check("the wrong way round stays dark") do
  bb = fresh(BLINK.sub("led c7 c9", "led c9 c7"))
  GPIO.new(2, GPIO::OUT).write(1)
  bb.led_current(led_id(bb)).abs < 1.0e-6
end
check("reset lets go of the pin") do
  bb = fresh(BLINK)
  GPIO.new(2, GPIO::OUT).write(1)
  GPIO.reset
  bb.led_current(led_id(bb)) < 1.0e-6
end
check("no warnings") do
  bb = fresh(BLINK)
  GPIO.new(2, GPIO::OUT).write(1)
  bb.warnings.empty?
end

SWITCH = <<~TEXT
  switch e11
  wire J1-6 a11
  wire J1-18 a13
TEXT

puts "A tact switch on GPIO3"
check("pull-up: high when open, low when pressed") do
  bb = fresh(SWITCH)
  pin = GPIO.new(3, GPIO::IN | GPIO::PULL_UP)
  up = pin.read
  bb.press(bb.parts[0][0])
  down = pin.read
  bb.release(bb.parts[0][0])
  up == 1 && down == 0 && pin.read == 1
end
check("the legs across the groove are joined") do
  bb = fresh("switch e11\nwire J1-6 j11\nwire J1-3 a13\n")
  pin = GPIO.new(3, GPIO::IN | GPIO::PULL_UP)
  bb.press(bb.parts[0][0])
  pin.read == 0
end
check("press and release arrive as edges") do
  bb = fresh(SWITCH)
  pin = GPIO.new(3, GPIO::IN | GPIO::PULL_UP)
  seen = []
  pin.irq(GPIO::EDGE_FALL | GPIO::EDGE_RISE) { |_p, e| seen << e }
  bb.press(bb.parts[0][0])
  bb.release(bb.parts[0][0])
  seen == [GPIO::EDGE_FALL, GPIO::EDGE_RISE]
end
check("no pull-up: floats while open") do
  bb = fresh(SWITCH)
  GPIO.new(3, GPIO::IN)
  !bb.solution.driven?(bb.node_for("GPIO3"))
end

puts "Mistakes"
check("an LED straight from a pin to GND: the missing resistor") do
  bb = fresh("wire J1-5 a3\nled b3 b5\nwire J1-3 c5\n")
  GPIO.new(2, GPIO::OUT).write(1)
  bb.warnings.any? { |w| w.include?("LED") && w.include?("抵抗") }
end
check("an LED straight from 5V: over its limit") do
  bb = fresh("wire J1-1 a3\nled b3 b5\nwire J1-3 c5\n")
  bb.warnings.any? { |w| w.include?("LED") && w.include?("壊れます") }
end
check("3V3 wired to GND") do
  bb = fresh("wire J1-4 J1-3\n")
  bb.warnings.any? { |w| w.include?("3V3") }
end
check("a pin driven high wired to GND") do
  bb = fresh("wire J1-5 J1-3\n")
  GPIO.new(2, GPIO::OUT).write(1)
  bb.warnings.any? { |w| w.include?("GPIO2") }
end
check("5 V into a pin") do
  bb = fresh("wire J1-1 a1\nresistor b1 b5\nwire J1-5 c5\n")
  GPIO.new(2, GPIO::IN)
  bb.warnings.any? { |w| w.include?("GPIO2") && w.include?("3.3 V") }
end

puts "Placing"
check("one leg per hole") do
  bb = fresh(BLINK)
  bb.place(:resistor, %w[b3 a20]).is_a?(String) && bb.place(:resistor, %w[b3 f3]).is_a?(String)
end
check("a switch goes on row e") { fresh.place(:switch, ["d3"]).is_a?(String) }
check("a switch needs two columns to its right") { fresh.place(:switch, ["e16"]).is_a?(String) }
check("text comes back the same") do
  bb = fresh(BLINK + SWITCH)
  bb.to_text == BLINK + SWITCH
end
check("a leg moves, the other stays") do
  bb = fresh(BLINK)
  GPIO.new(2, GPIO::OUT).write(1)
  id, k = bb.leg_at("c9")
  moved = bb.move_leg(id, k, "c10").nil?
  # The cathode now sits on column 10, which nothing grounds: dark.
  dark = bb.led_current(led_id(bb)) < 1.0e-6
  back = bb.move_leg(id, k, "d9").is_a?(String)   # the ground wire is there
  moved && dark && back && bb.part(id)[2] == ["c7", "c10"]
end
check("a leg can go to a free hole, not onto another leg") do
  bb = fresh(BLINK)
  id, k = bb.leg_at("c7")
  bb.move_leg(id, k, "c9").is_a?(String) &&     # the other leg is there
    bb.move_leg(id, k, "e9").nil?               # free, even on the other leg's strip
end

check("a bad line is reported, the rest placed") do
  bb = Breadboard.new
  errors = bb.load_text("wire J1-5 a3\nled z1 a2\n")
  errors.size == 1 && errors[0].start_with?("2 行目") && bb.parts.size == 1
end

puts "Wiring written in a program's comments"
check("the breadboard sample's wiring is read, and lights its LED") do
  text = Breadboard.wiring_in(File.read("sim/examples/breadboard_led.rb")) rescue nil
  bb = fresh(text.to_s)
  GPIO.new(2, GPIO::OUT).write(1)
  text == "wire J1-5 a13\nresistor b13 b9\nled c9 g10\nwire h10 J1-3\n" &&
    bb.led_current(led_id(bb)) > 0.00055 && bb.warnings.empty?
end
check("notes after the holes are left out, other comments ignored") do
  Breadboard.wiring_in("# led c7 c9 long leg first\n# wire is a word\n# switch e3\nputs 1\n") ==
    "led c7 c9\nswitch e3\n"
end
check("no wiring, no text") { Breadboard.wiring_in("# just a program\nputs 1\n").nil? }

puts "Clicks to holes (BoardView)"
check("every hole is found at its own centre") do
  ok = true
  r = 0
  while r < 10
    c = 1
    while c <= 17
      name = Breadboard.hole_name(r, c)
      xy = BoardView.hole_xy(name)
      ok = false unless BoardView.hole_near(xy[0], xy[1]) == name
      c += 1
    end
    r += 1
  end
  n = 1
  while n <= 20
    xy = BoardView.hole_xy("J1-#{n}")
    ok = false unless BoardView.hole_near(xy[0], xy[1]) == "J1-#{n}"
    n += 1
  end
  ok
end
check("a little off still counts") do
  xy = BoardView.hole_xy("c7")
  BoardView.hole_near(xy[0] + 1.0, xy[1] - 1.0) == "c7"
end
check("the groove and the edge are no hole") do
  mid = BoardView.hole_xy("e7")
  f = BoardView.hole_xy("f7")
  BoardView.hole_near(mid[0], (mid[1] + f[1]) / 2.0).nil? &&
    BoardView.hole_near(BoardLayout::BREADBOARD_CENTER[0] - 23.0, mid[1]).nil?
end

puts "The buttons are left alone"
check("a button pin still reads its press") do
  fresh(BLINK)
  b = GPIO.new(17, GPIO::IN | GPIO::PULL_UP)
  up = b.read
  GPIO.press(17)
  up == 1 && b.read == 0
end

puts
puts "#{$checks - $failures}/#{$checks} checks passed"
if 0 < $failures
  puts "FAILED"
else
  puts "OK"
end
