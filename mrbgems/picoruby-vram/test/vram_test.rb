# The runner also loads this file into the rake process (CRuby) to find the
# test classes. There is no VRAM there, so nothing at the top level may name
# it: the helper class is only made where the gem exists.
begin
  require "vram"
rescue LoadError
end

# What a display driver gets from VRAM::Delegatable: the wrappers have to hand
# `color:` on, or a gray8 page can only ever be drawn at level 1.
if Object.const_defined?(:VRAM)
  class Delegating
    include VRAM::Delegatable
    attr_reader :vram

    def initialize
      @vram = VRAM.new(w: 16, h: 16, cols: 1, rows: 1, layout: :gray8)
      @width = 16
      @height = 16
    end

    def level(x, y)
      @vram.pages[0][2].getbyte(y * 16 + x)
    end
  end
end

class VRAMTest < Picotest::Test
  def test_delegated_draw_bytes_passes_color
    d = Delegating.new
    d.draw_bytes(x: 0, y: 0, w: 8, h: 1, data: "\x80", color: 200)
    assert_equal 200, d.level(0, 0)
    assert_equal 0, d.level(1, 0)
  end

  def test_delegated_draw_bytes_defaults_to_one
    d = Delegating.new
    d.draw_bytes(x: 0, y: 0, w: 8, h: 1, data: "\x80")
    assert_equal 1, d.level(0, 0)
  end

  def test_delegated_draw_bitmap_passes_color
    d = Delegating.new
    d.draw_bitmap(x: 0, y: 0, w: 8, h: 1, data: [0x80], color: 77)
    assert_equal 77, d.level(0, 0)
  end

  def test_delegated_draw_bitmap_defaults_to_one
    d = Delegating.new
    d.draw_bitmap(x: 0, y: 0, w: 8, h: 1, data: [0x80])
    assert_equal 1, d.level(0, 0)
  end
end
