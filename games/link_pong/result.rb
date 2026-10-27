module LinkPong
  class Result
    BRIGHTNESS = 0x40
    BIG_UP_TO    = 99                    # ここまでは縦横 2 倍で出す

    def initialize(matrix, buttons, sound, returns)
      @matrix = matrix
      @buttons = buttons
      @sound = sound
      @returns = returns
    end

    def run
      @matrix.clear
      draw_number(@returns)
      @matrix.show
      @sound.result
      @buttons.clear_presses
      sleep_ms 20 until any_button_pressed?
      @sound.stop
    end

    private

    def draw_number(number)
      text = number.to_s
      scale = number <= BIG_UP_TO ? 2 : 1
      left = (LedMatrix::WIDTH - Font.width(text, scale) + 1) / 2 + 1
      top = (LedMatrix::HEIGHT - Font::HEIGHT * scale) / 2 + 1
      Font.draw(@matrix, text, left, top, BRIGHTNESS, scale)
    end

    def any_button_pressed?
      pressed = false
      @buttons.each_press { pressed = true }
      pressed
    end
  end
end
