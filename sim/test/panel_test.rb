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
# leaves empty, so point it at the working directory.
$LOAD_PATH = ["."]
# sim_panel.rb first: it defines I2C and tolerates the driver's `require 'i2c'`.
load "sim/sim_panel.rb"
load "mrbgems/picoruby-is31fl3729/mrblib/is31fl3729.rb"

# LedMatrix is what the page drives, so the test drives the same thing: the
# real IS31FL3729 driver behind it, two virtual chips on one virtual bus.
def new_board(global_current: 0x20)
  m = LedMatrix.new(global_current: global_current)
  [m.panel, m.top, m.bottom, m]
end

def light(m, x, y, pwm = 0xFF)
  m.set(x, y, pwm)
  m.show
end

puts "1. every one of the 256 pixels lights alone"
panel, top, bottom, m = new_board
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
panel, top, bottom, m = new_board
bottom.set_dot(1, 16, 0xFF) # CS16 on the second chip
bottom.flush
check("chip CS16 shows at x = 1, y = 9") { 0.0 < panel.brightness(1, 9) }
check("and nowhere else on that row")    { panel.brightness(16, 9) == 0.0 }

panel, top, bottom, m = new_board
top.set_dot(1, 16, 0xFF) # CS16 on the first chip
top.flush
check("chip CS16 shows at x = 16, y = 1 on the top half") { 0.0 < panel.brightness(16, 1) }

puts "3. the chip boundary sits between rows 8 and 9"
panel, top, bottom, m = new_board
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
panel, top, bottom, m = new_board
top.fill(0xFF); top.flush
check("lit before shutdown") { 0.0 < panel.brightness(1, 1) }
top.shutdown
check("dark after shutdown") { panel.brightness(1, 1) == 0.0 }
top.resume
check("lit again after resume") { 0.0 < panel.brightness(1, 1) }

puts "6. an L drawn across the chip boundary looks like an L"
panel, top, bottom, m = new_board
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
panel, top, bottom, m = new_board
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
  _p2, _t2, _b2, m2 = new_board(global_current: 0x40)
  m2.set(1, 1); m2.show
  levels[0].to_i < m2.panel.levels[0].to_i
end

puts
puts "#{$checks - $failures}/#{$checks} checks passed"
if 0 < $failures
  puts "FAILED"
else
  puts "OK"
end
