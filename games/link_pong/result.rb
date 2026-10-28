module LinkPong
  class Result
    BRIGHTNESS = 0x40
    BIG_UP_TO    = 99                    # ここまでは縦横 2 倍で出す

    include Screen

    def initialize(matrix, buttons, sound, returns)
      @matrix = matrix
      @buttons = buttons
      @sound = sound
      @returns = returns
    end

    def run
      repaint { draw_number(@returns) }
      @sound.result
      @buttons.clear_presses
      sleep_ms 20 until any_button_pressed?
      @sound.stop
    end

    private

    def draw_number(number)
      scale = number <= BIG_UP_TO ? 2 : 1
      draw_centered_text(number.to_s, BRIGHTNESS, scale)
    end
  end
end
