# Headless check of the breadboard's circuit solver (sim/sim_circuit.rb): the
# currents the kit's parts should give, and the mistakes it should catch.
#
#   bin/picoruby sim/test/circuit_test.rb
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

def ma(amps)
  (amps * 1000.0).round(3)
end

$LOAD_PATH = ["."]
load "sim/sim_circuit.rb"

# A GPIO driving its pin: 3.3 V behind a few tens of ohms, good for 12 mA.
def gpio_high(c, node)
  c.source(node, 3.3, 50, 0.012, :gpio)
end

def led_through(ohms_list)
  c = Circuit.new
  gpio_high(c, :pin)
  prev = :pin
  i = 0
  while i < ohms_list.size
    nxt = "r#{i}"
    c.resistor(prev, nxt, ohms_list[i], "R#{i}")
    prev = nxt
    i += 1
  end
  c.led(prev, :gnd, :led)
  c.solve
end

puts "LED brightness with the kit's two 1 kOhm resistors"
one = led_through([1000]).current(:led)
two = led_through([1000, 1000]).current(:led)
par = Circuit.new
gpio_high(par, :pin)
par.resistor(:pin, :a, 1000, :r1).resistor(:pin, :a, 1000, :r2).led(:a, :gnd, :led).solve
parallel = par.current(:led)
puts "       one #{ma(one)} mA, two in series #{ma(two)} mA, two side by side #{ma(parallel)} mA"
check("one resistor: about 1.4 mA") { one > 0.00130 && one < 0.00150 }
check("two in series: about half") { two / one > 0.45 && two / one < 0.58 }
check("two side by side: about double") { parallel / one > 1.7 && parallel / one < 2.1 }
check("the LED drops about 1.8 V") do
  c = led_through([1000])
  v = c.voltage("r0")
  v > 1.75 && v < 1.90
end
check("no warnings with a resistor") { led_through([1000]).warnings.empty? }

puts "Mistakes"
check("an LED the wrong way round stays dark") do
  c = Circuit.new
  gpio_high(c, :pin)
  c.resistor(:pin, :a, 1000, :r).led(:gnd, :a, :led).solve
  c.current(:led).abs < 1.0e-6
end
check("an LED with no resistor: the pin and the LED are both over") do
  c = Circuit.new
  gpio_high(c, :pin)
  c.led(:pin, :gnd, :led).solve
  kinds = c.warnings.map { |w| [w[0], w[1]] }
  kinds.include?([:overcurrent, :gpio]) && kinds.include?([:led_overcurrent, :led])
end
check("3V3 shorted to GND through a switch") do
  c = Circuit.new
  c.source(:v33, 3.3, 0.1, 0.3, :rail)
  c.switch(:v33, :gnd, true, :sw).solve
  c.warnings.any? { |w| w[0] == :overcurrent && w[1] == :rail }
end
check("5 V through a resistor reaches the point at 5 V") do
  c = Circuit.new
  c.source(:v5, 5.0, 0.1, 0.5, :rail)
  c.resistor(:v5, :pin, 1000, :r).solve
  (c.voltage(:pin) - 5.0).abs < 0.01
end

puts "Reading a switch"
pulled = lambda do |closed|
  c = Circuit.new
  c.source(:pin, 3.3, 50_000, 1.0, :pull_up)  # the pin's own pull-up
  c.switch(:pin, :gnd, closed, :sw).solve
end
check("open switch with pull-up reads high") do
  c = pulled.call(false)
  c.driven?(:pin) && c.voltage(:pin) > 3.2
end
check("closed switch with pull-up reads low") do
  c = pulled.call(true)
  c.driven?(:pin) && c.voltage(:pin) < 0.01
end
check("no pull-up, switch open: the pin floats") do
  c = Circuit.new
  c.switch(:pin, :gnd, false, :sw)
  c.resistor(:pin, :other, 1000, :r).solve
  !c.driven?(:pin)
end
check("behind a dark LED counts as floating") do
  c = Circuit.new
  c.led(:gnd, :pin, :led).solve
  !c.driven?(:pin)
end

puts "Sinking"
check("a GPIO at 0 V lights an LED from 3V3") do
  c = Circuit.new
  c.source(:v33, 3.3, 0.1, 0.3, :rail)
  c.source(:pin, 0.0, 50, 0.012, :gpio)
  c.resistor(:v33, :a, 1000, :r).led(:a, :pin, :led).solve
  a = c.current(:led)
  a > 0.00130 && a < 0.00150 && c.current(:gpio) < 0
end

puts
puts "#{$checks - $failures}/#{$checks} checks passed"
if 0 < $failures
  puts "FAILED"
else
  puts "OK"
end
