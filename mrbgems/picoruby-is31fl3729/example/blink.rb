# Walks a single lit dot across a 16x8 matrix.
#
# Wiring assumed here: I2C0 on GPIO4/5, AD tied to GND (address 0x34) and SDB
# driven by GPIO24 through a filter, which is why it is raised and given time
# to settle before the first transaction.
require 'gpio'
require 'i2c'
require 'is31fl3729'

sdb = GPIO.new(24, GPIO::OUT)
sdb.write 1
sleep_ms 1 # the board's SDB filter needs a few hundred microseconds

i2c = I2C.new(unit: :RP2040_I2C0, sda_pin: 4, scl_pin: 5, frequency: 400_000)
led = IS31FL3729.new(i2c: i2c, address: IS31FL3729::ADDRESS_GND)

# Conservative: this is peak current per dot, and every lit dot adds up.
led.setup(global_current: 0x10)

sw = 1
cs = 1
while true
  led.clear
  led.set_dot(sw, cs, 0xFF)
  led.flush
  sleep_ms 60
  cs += 1
  if led.columns < cs
    cs = 1
    sw += 1
    sw = 1 if led.rows < sw
  end
end
