# The 16x16 matrix, built from two IS31FL3729.
#
# Rows 1..8 are the chip at 0x34 and rows 9..16 the one at 0x35, whose columns
# are wired in reverse. Both facts come from the r1 netlist; see
# dev-docs/led-matrix-gem/hardware.md section 4.
class LedMatrix
  WIDTH  = 16
  HEIGHT = 16

  TOP_ADDRESS    = 0x34
  BOTTOM_ADDRESS = 0x35

  attr_reader :top, :bottom

  def initialize(i2c:, global_current: 0x20)
    @top = IS31FL3729.new(i2c: i2c, address: TOP_ADDRESS)
    @bottom = IS31FL3729.new(i2c: i2c, address: BOTTOM_ADDRESS)
    @global_current = global_current
    @top.setup(global_current: global_current)
    @bottom.setup(global_current: global_current)
    @pen = 0xFF
  end

  # x and y are 1-based. The third argument is how bright the dot should
  # look, 0..255, not the chip's duty: see duty_of.
  def set(x, y, pwm = 0xFF)
    return self if x < 1 || WIDTH < x || y < 1 || HEIGHT < y
    pwm = duty_of(pwm)
    if y <= 8
      @top.set_dot(y, x, pwm)
    else
      # The bottom chip has its columns reversed.
      @bottom.set_dot(y - 8, WIDTH + 1 - x, pwm)
    end
    self
  end

  def clear
    @top.clear
    @bottom.clear
    self
  end

  def fill(pwm = 0xFF)
    pwm = duty_of(pwm)
    @top.fill(pwm)
    @bottom.fill(pwm)
    self
  end

  # The chip's PWM is linear in light, and the eye is not: on the real board
  # 0x0F still looks a third lit and 0xC0 is hard to tell from 0xFF. Squaring
  # the value (gamma 2.0) makes 0..255 read as brightness instead. Every dot
  # passes through set, including blit, so this is the one place it happens;
  # the VRAM keeps the values the drawing was made with. Rounded up so that
  # anything above zero still lights.
  def duty_of(v)
    return 0 if v <= 0
    return 255 if 255 <= v
    (v * v + 254) / 255
  end

  # Nothing reaches the chips until this runs.
  def show
    @top.flush
    @bottom.flush
    self
  end

  # 0..0x40. Start low: the matrix at full tilt draws 330mA, and the 5V rail is
  # not protected against going past what USB will give (see hardware.md 5-4).
  def brightness=(value)
    @global_current = value
    @top.global_current = value
    @bottom.global_current = value
    value
  end

  def brightness
    @global_current
  end

  # --- drawing ------------------------------------------------------------
  #
  # The VRAM is 8 bits deep, so a line, a rectangle and a glyph all carry a
  # brightness of their own — the same 0..255 that `set` takes. `pen` is what
  # they use when none is given, which is also how a font bitmap gets its
  # brightness, since BDFFont calls draw_bitmap without one.
  #
  # picoruby-shinonome carries the 16x16 JIS font, which is the whole reason
  # this panel is 16x16 rather than 12x12.
  begin
    include Shinonome::Drawable
  rescue NameError
    # No picoruby-shinonome in this build; only the shape API is available.
  end

  # The brightness the drawing methods use when none is given, 0..255.
  attr_accessor :pen

  # Built on first use: a board without picoruby-vram can still light dots.
  #
  # Two pages, one per driver chip, so that a change confined to one half can
  # be pushed without touching the other.
  def vram
    @vram ||= VRAM.new(w: WIDTH, h: HEIGHT, cols: 1, rows: 2, layout: :gray8)
  end

  # What BDFFont::Drawable calls, and so what makes draw_shinonome work. The
  # font is a bitmap, so its pixels take the pen.
  def draw_bitmap(x:, y:, w:, h:, data:, color: nil)
    vram.draw_bitmap(x: x, y: y, w: w, h: h, data: data, color: color || @pen)
    nil
  end

  def draw_text(text, x = 0, y = 0, font: "go16")
    draw_shinonome(font, x, y, text)
    self
  end

  def set_pixel(x, y, color = nil)
    vram.set_pixel(x, y, color || @pen)
    self
  end

  def draw_line(x0, y0, x1, y1, color = nil)
    vram.draw_line(x0, y0, x1, y1, color || @pen)
    self
  end

  def draw_rect(x, y, w, h, color = nil)
    vram.draw_rect(x, y, w, h, color || @pen)
    self
  end

  def clear_drawing
    vram.fill(0)
    self
  end

  # Copy the drawing buffer onto the dots. Both are a byte per pixel now, so
  # this is a straight copy: the buffer holds the brightness the drawing was
  # made with.
  def blit
    pages = vram.pages
    pi = 0
    while pi < pages.size
      page = pages[pi]
      top = page[1].to_i * 8
      data = page[2].to_s
      ly = 0
      while ly < 8
        x = 0
        while x < WIDTH
          set(x + 1, top + ly + 1, data.getbyte(ly * WIDTH + x) || 0)
          x += 1
        end
        ly += 1
      end
      pi += 1
    end
    self
  end
end
