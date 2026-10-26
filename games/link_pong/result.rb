module LinkPong
  class Result
    BRIGHTNESS = 0x40
    WIN = [
      "................",
      "................",
      "..#.#.###.#.#...",
      "..#.#.#.#.#.#...",
      "...#..#.#.#.#...",
      "...#..#.#.#.#...",
      "...#..###.###...",
      "................",
      "................",
      ".#...#.#.#..#.#.",
      ".#...#.#.##.#.#.",
      ".#.#.#.#.#.##.#.",
      ".##.##.#.#..#...",
      ".#...#.#.#..#.#.",
      "................",
      "................"
    ]
    LOSE = [
      "................",
      "................",
      "..#.#.###.#.#...",
      "..#.#.#.#.#.#...",
      "...#..#.#.#.#...",
      "...#..#.#.#.#...",
      "...#..###.###...",
      "................",
      "................",
      "#...###..##.###.",
      "#...#.#.#...#...",
      "#...#.#..#..###.",
      "#...#.#...#.#...",
      "###.###.##..###.",
      "................",
      "................"
    ]

    def initialize(matrix, buttons, sound, won)
      @matrix = matrix
      @buttons = buttons
      @sound = sound
      @won = won
    end

    def run
      @matrix.clear
      draw(@won ? WIN : LOSE)
      @matrix.show
      @won ? @sound.win : @sound.lose
      @buttons.clear_presses
      sleep_ms 20 until any_button_pressed?
      @sound.stop
    end

    private

    def any_button_pressed?
      pressed = false
      @buttons.each_press { pressed = true }
      pressed
    end

    def draw(rows)
      y = 1
      while y <= LedMatrix::HEIGHT
        x = 1
        while x <= LedMatrix::WIDTH
          @matrix.set(x, y, BRIGHTNESS) if rows[y - 1][x - 1] == "#"
          x += 1
        end
        y += 1
      end
    end
  end
end
