module LinkPong
  class Result
    BRIGHTNESS = 0x40

    include Screen

    def initialize(matrix, buttons, sound, text)
      @matrix = matrix
      @buttons = buttons
      @sound = sound
      @text = text
    end

    def run
      repaint { draw_centered_text(@text, BRIGHTNESS, scale) }
      @sound.result
      @buttons.clear_presses
      sleep_ms 20 until any_button_pressed?
      @sound.stop
    end

    private

    def scale = Font.width(@text, 2) <= LedMatrix::WIDTH ? 2 : 1
  end
end
