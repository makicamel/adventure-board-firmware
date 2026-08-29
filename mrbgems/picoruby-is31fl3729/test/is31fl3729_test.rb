# Stand-in for picoruby-i2c, which is platform dependent (it has no posix port)
# and so is absent from the host test binary. Every transaction is recorded
# flattened to the bytes that would go on the wire, so the tests can assert on
# exactly what the chip would receive.
#
# It lives in this file rather than under test/mock/ because Picotest::Runner
# embeds only the one test file into the script it hands to the target VM
# (see Picotest::Runner#run_test); a sibling file would be loaded into the rake
# process and never reach the VM under test.
class I2C
  attr_reader :writes
  attr_accessor :read_data

  def initialize(unit: nil, frequency: 100_000, sda_pin: -1, scl_pin: -1, timeout: 1000)
    @writes = []
    @read_data = ""
  end

  def write(address, *outputs, timeout: nil, nostop: false)
    bytes = ""
    i = 0
    while i < outputs.size
      out = outputs[i]
      if out.is_a?(Integer)
        bytes << out.chr
      elsif out.is_a?(String)
        bytes << out
      elsif out.is_a?(Array)
        j = 0
        while j < out.size
          bytes << out[j].to_i.chr
          j += 1
        end
      else
        raise ArgumentError, "unsupported output: #{out.class}"
      end
      i += 1
    end
    @writes << [address, bytes]
    bytes.bytesize
  end

  def read(address, len, *outputs, timeout: nil)
    write(address, *outputs) unless outputs.empty?
    @read_data[0, len].to_s
  end

  def scan(timeout: nil)
    nil
  end

  # Last transaction as [address, bytes], or nil when nothing was sent.
  def last_write
    @writes[-1]
  end

  def clear
    @writes = []
  end
end

class IS31FL3729Test < Picotest::Test
  def setup
    require "is31fl3729"
    @i2c = I2C.new
    @led = IS31FL3729.new(i2c: @i2c)
  end

  # --- register mapping -----------------------------------------------------
  #
  # (sw - 1) * 0x10 + cs. The one that is easy to get wrong is CS16: it takes
  # the slot right after CS15, which is why the rows end up contiguous.

  def test_register_of_first_row
    assert_equal 0x01, @led.register_of(1, 1)
    assert_equal 0x0F, @led.register_of(1, 15)
    assert_equal 0x10, @led.register_of(1, 16)
  end

  def test_register_of_last_row
    assert_equal 0x71, @led.register_of(8, 1)
    assert_equal 0x80, @led.register_of(8, 16)
  end

  def test_rows_are_contiguous
    # The last register of a row and the first of the next differ by one, so a
    # whole frame can go out as one auto-incrementing write.
    assert_equal @led.register_of(2, 1), @led.register_of(1, 16) + 1
    assert_equal @led.register_of(8, 1), @led.register_of(7, 16) + 1
  end

  # --- buffer ---------------------------------------------------------------

  def test_frame_size_is_rows_times_stride
    assert_equal 128, @led.frame.bytesize
  end

  def test_set_dot_lands_at_register_minus_one
    @led.set_dot(1, 1, 0x11)
    @led.set_dot(1, 16, 0x22)
    @led.set_dot(8, 16, 0x33)
    frame = @led.frame
    assert_equal 0x11, frame.getbyte(0x00)
    assert_equal 0x22, frame.getbyte(0x0F)
    assert_equal 0x33, frame.getbyte(0x7F)
  end

  def test_dot_reads_back
    @led.set_dot(4, 9, 0xAB)
    assert_equal 0xAB, @led.dot(4, 9)
    assert_equal 0, @led.dot(4, 10)
  end

  def test_out_of_range
    assert_raise(RangeError) { @led.set_dot(0, 1, 1) }
    assert_raise(RangeError) { @led.set_dot(9, 1, 1) }
    assert_raise(RangeError) { @led.set_dot(1, 0, 1) }
    assert_raise(RangeError) { @led.set_dot(1, 17, 1) }
  end

  def test_frame_assignment_rejects_wrong_size
    assert_raise(ArgumentError) { @led.frame = "\x00" * 127 }
  end

  # --- I2C traffic ----------------------------------------------------------

  def test_a_full_frame_is_one_transaction
    @led.frame = "\xFF" * 128
    @i2c.clear
    @led.flush
    assert_equal 1, @i2c.writes.size
    address, bytes = @i2c.last_write
    assert_equal 0x34, address
    # One register address followed by the whole buffer.
    assert_equal 129, bytes.bytesize
    assert_equal IS31FL3729::PWM_BASE, bytes.getbyte(0)
    assert_equal 0xFF, bytes.getbyte(1)
    assert_equal 0xFF, bytes.getbyte(128)
  end

  def test_flush_writes_only_the_dirty_range
    @led.flush # drop the initial full-frame dirty range
    @i2c.clear
    @led.set_dot(2, 3, 0x40)
    @led.set_dot(2, 5, 0x50)
    @led.flush
    address, bytes = @i2c.last_write
    # Offsets 0x12..0x14 inclusive: three data bytes behind the address.
    assert_equal IS31FL3729::PWM_BASE + 0x12, bytes.getbyte(0)
    assert_equal 4, bytes.bytesize
    assert_equal 0x40, bytes.getbyte(1)
    assert_equal 0x00, bytes.getbyte(2)
    assert_equal 0x50, bytes.getbyte(3)
  end

  def test_flush_is_a_no_op_when_clean
    @led.flush
    @i2c.clear
    assert_false @led.dirty?
    assert_false @led.flush
    assert_equal 0, @i2c.writes.size
  end

  # --- configuration --------------------------------------------------------

  def test_configuration_value_for_eight_rows
    @i2c.clear
    @led.configure
    _address, bytes = @i2c.last_write
    assert_equal IS31FL3729::CONFIGURATION, bytes.getbyte(0)
    # SWS=0b0001 (8 rows) | LGC | SSD
    assert_equal 0x19, bytes.getbyte(1)
  end

  def test_configuration_value_for_nine_rows
    led = IS31FL3729.new(i2c: @i2c, rows: 9, logic_high: false)
    assert_equal 15, led.columns
    @i2c.clear
    led.configure
    _address, bytes = @i2c.last_write
    # SWS=0b0000 (9 rows), no LGC, SSD only
    assert_equal 0x01, bytes.getbyte(1)
  end

  def test_shutdown_clears_ssd_only
    @i2c.clear
    @led.shutdown
    _address, bytes = @i2c.last_write
    assert_equal 0x18, bytes.getbyte(1)
  end

  def test_rows_out_of_range
    assert_raise(ArgumentError) { IS31FL3729.new(i2c: @i2c, rows: 1) }
    assert_raise(ArgumentError) { IS31FL3729.new(i2c: @i2c, rows: 10) }
  end

  def test_global_current_is_clamped
    @i2c.clear
    @led.global_current = 0xFF
    _address, bytes = @i2c.last_write
    assert_equal IS31FL3729::GLOBAL_CURRENT_MAX, bytes.getbyte(1)
  end

  def test_scaling_all_covers_sixteen_registers
    @i2c.clear
    @led.scaling_all = 0x80
    _address, bytes = @i2c.last_write
    assert_equal IS31FL3729::SCALING_BASE, bytes.getbyte(0)
    assert_equal 17, bytes.bytesize
    assert_equal 0x80, bytes.getbyte(16)
  end

  # --- setup ----------------------------------------------------------------

  def test_setup_writes_current_and_scaling
    # Power-on leaves both at zero, so a chip that is only reset stays dark.
    @i2c.clear
    @led.setup(global_current: 0x20)
    registers = []
    i = 0
    writes = @i2c.writes
    while i < writes.size
      registers << writes[i][1].getbyte(0)
      i += 1
    end
    assert_equal IS31FL3729::RESET, registers[0]
    assert_equal IS31FL3729::CONFIGURATION, registers[1]
    assert_equal IS31FL3729::GLOBAL_CURRENT, registers[2]
    assert_equal IS31FL3729::SCALING_BASE, registers[3]
    assert_equal IS31FL3729::PWM_BASE, registers[4]
    assert_equal 5, registers.size
  end

  def test_reset_value
    @i2c.clear
    @led.reset
    _address, bytes = @i2c.last_write
    assert_equal IS31FL3729::RESET, bytes.getbyte(0)
    assert_equal 0xAE, bytes.getbyte(1)
  end

  def test_address_selection
    led = IS31FL3729.new(i2c: @i2c, address: IS31FL3729::ADDRESS_SCL)
    assert_equal 0x35, led.address
  end
end
