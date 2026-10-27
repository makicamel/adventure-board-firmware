module LinkPong
  class Result
    BRIGHTNESS = 0x40
    DIGITS = {
      "0" => ["###", "#.#", "#.#", "#.#", "###"],
      "1" => [".#.", "##.", ".#.", ".#.", "###"],
      "2" => ["###", "..#", "###", "#..", "###"],
      "3" => ["###", "..#", "###", "..#", "###"],
      "4" => ["#.#", "#.#", "###", "..#", "..#"],
      "5" => ["###", "#..", "###", "..#", "###"],
      "6" => ["###", "#..", "###", "#.#", "###"],
      "7" => ["###", "..#", "..#", "..#", "..#"],
      "8" => ["###", "#.#", "###", "#.#", "###"],
      "9" => ["###", "#.#", "###", "..#", "###"]
    }
    DIGIT_WIDTH  = 3
    DIGIT_HEIGHT = 5
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
      step = (DIGIT_WIDTH + 1) * scale
      left = (LedMatrix::WIDTH - (text.size * step - scale) + 1) / 2 + 1
      top = (LedMatrix::HEIGHT - DIGIT_HEIGHT * scale) / 2 + 1
      text.size.times { |i| draw_digit(DIGITS[text[i]], left + i * step, top, scale) }
    end

    def draw_digit(rows, left, top, scale)
      DIGIT_HEIGHT.times do |row|
        DIGIT_WIDTH.times do |column|
          next unless rows[row][column] == "#"
          scale.times do |dy|
            scale.times { |dx| @matrix.set(left + column * scale + dx, top + row * scale + dy, BRIGHTNESS) }
          end
        end
      end
    end

    def any_button_pressed?
      pressed = false
      @buttons.each_press { pressed = true }
      pressed
    end
  end
end
