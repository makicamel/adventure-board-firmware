module LinkPong
  module Screen
    private

    def repaint
      @matrix.clear
      yield
      @matrix.show
    end

    def draw_centered_text(text, brightness, scale = 1)
      left = (LedMatrix::WIDTH - Font.width(text, scale) + 1) / 2 + 1
      top = (LedMatrix::HEIGHT - Font::HEIGHT * scale) / 2 + 1
      draw_text(text, left, top, brightness, scale)
    end

    def draw_text(text, left, top, brightness, scale = 1)
      glyph_left = left
      text.size.times do |i|
        glyph = Font::GLYPHS[text[i]]
        glyph.each_with_index do |row, y|
          row.size.times do |x|
            fill_square(glyph_left + x * scale, top + y * scale, scale, brightness) if row[x] == "#"
          end
        end
        glyph_left += (glyph[0].size + 1) * scale
      end
    end

    def fill_square(left, top, size, brightness)
      size.times { |dy| size.times { |dx| @matrix.set(left + dx, top + dy, brightness) } }
    end

    def any_button_pressed?
      pressed = false
      @buttons.each_press { pressed = true }
      pressed
    end
  end
end
