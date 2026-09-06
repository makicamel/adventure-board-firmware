# picoruby-is31fl3729

Driver for the Lumissil **IS31FL3729** matrix LED driver: up to 16 columns (CS)
by 9 rows (SW), 8-bit PWM per dot, self-scanning, I2C.

One instance owns one chip. A panel built from several chips composes
instances — the chip has no SYNC pin, and nothing is shared between two of them
but the bus, so ganging them is a board concern rather than a driver one.

## Usage

```ruby
require 'i2c'
require 'is31fl3729'

i2c = I2C.new(unit: :RP2040_I2C0, sda_pin: 4, scl_pin: 5, frequency: 400_000)

led = IS31FL3729.new(i2c: i2c, address: IS31FL3729::ADDRESS_GND, rows: 8)
led.setup(global_current: 0x20)   # reset, configure, current, scaling, clear

led.set_dot(1, 1, 0xFF)           # row 1, column 1, full brightness
led.set_dot(8, 16, 0x40)
led.flush                         # only the changed range goes out
```

Addresses follow the AD pin: `ADDRESS_GND` 0x34, `ADDRESS_SCL` 0x35,
`ADDRESS_SDA` 0x36, `ADDRESS_VCC` 0x37.

### Whole frames

A display layer that renders elsewhere hands the finished bytes over, which
keeps the per-pixel work out of this class:

```ruby
led.frame = rendered   # rows * 16 bytes
led.flush
```

## Three things that bite

**Power-on leaves the chip dark even after a correct reset.** Both the global
current (0xA1) and the scaling registers (0x90..0x9F) come up at 0, which means
no current at all. `#setup` writes both; a hand-rolled init that only resets
and sets the configuration register will look correct and show nothing.

**`SDB` is not handled here.** The pin is usually shared between chips and is
often filtered, so the settling time is a property of the board, not of the
chip. Raise it and wait before constructing the driver.

**The transaction after turning `LGC` on is lost.** Not in the datasheet;
measured on the chip. Whatever follows the configuration write that sets the
2.4V/0.6V logic levels is NACKed, no matter how long the gap (20ms changed
nothing), and if that was a write the chip then answers reads one
transaction late for a while. `#configure` spends a read there when `LGC`
goes 0 -> 1, once per reset, so `#setup` comes out clean. Nothing to do on
the caller's side; it is only worth knowing if you talk to the register
yourself.

## Register layout

The PWM byte of a dot lives at `(sw - 1) * 0x10 + cs`, so CS16 takes the slot
right after CS15 and the rows end up contiguous from 0x01:

| | CS1 | … | CS15 | CS16 |
|---|---|---|---|---|
| SW1 | 0x01 | … | 0x0F | 0x10 |
| SW2 | 0x11 | … | 0x1F | 0x20 |
| SW8 | 0x71 | … | 0x7F | 0x80 |

Together with the chip's address auto-increment, that makes a full 16×8 frame a
single 129-byte I2C transaction.

## Row count

`rows:` selects the scan mode (SWS in the configuration register). SW9 doubles
as CS16, so running all 9 rows is what costs the 16th column:

| `rows:` | matrix | SWS |
|---|---|---|
| 9 | 9 × 15 | 0b0000 |
| 8 | 8 × 16 | 0b0001 |
| 7 | 7 × 16 | 0b0010 |
| … | … | … |
| 2 | 2 × 16 | 0b0111 |

## Current

```
IOUT(PEAK) = 342 / RISET × (GCC / 64) × (SL / 256)
```

`RISET` is set in hardware, `GCC` is `#global_current=` (0..0x40) and `SL` is
the scaling register of the column. Start low and measure: the driver cannot
know the board's supply budget.

## Testing

```console
rake 'test:gems:picoruby[picoruby-is31fl3729]'
```

The test file carries a stand-in for `picoruby-i2c` (which has no posix port
and so cannot be linked on the host) that records the exact bytes that would
reach the bus. No hardware needed.
