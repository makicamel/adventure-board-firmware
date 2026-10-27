module LinkPong
  class Court
    OFF        = 0
    NET_BRIGHT = 0x18
    NET_X      = LedMatrix::WIDTH / 2 + 1

    attr_reader :top, :bottom, :left, :right

    def initialize(matrix, top:, bottom:, left:, right:)
      @matrix = matrix
      @top = top
      @bottom = bottom
      @left = left
      @right = right
    end

    def middle = (@top + @bottom) / 2

    def set(x, y, brightness)
      @matrix.set(x, y, brightness)
    end

    def redraw_background(x, y)
      @matrix.set(x, y, background_at(x, y))
    end

    def flush = @matrix.show

    def background_at(x, y) = OFF
  end

  class TitleCourt < Court
    LOGO = [
      "#...###.#..#.#.#",
      "#....#..##.#.#.#",
      "#....#..#.##.##.",
      "#....#..#..#.#.#",
      "###.###.#..#.#.#",
      "........+.......",
      "................",
      "........+.......",
      "................",
      "........+.......",
      "................",
      "##..###.#..#..##",
      "#.#.#.#.##.#.#..",
      "##..#.#.#.##.#.#",
      "#...#.#.#..#.#.#",
      "#...###.#..#..##"
    ]
    LOGO_BRIGHT = 0x20

    def initialize(matrix)
      super(matrix, top: 6, bottom: 11, left: 2, right: 15)
    end

    def draw
      @matrix.clear
      draw_logo
    end

    def background_at(x, y)
      c = LOGO[y - 1][x - 1]
      if c == "#"
        LOGO_BRIGHT
      elsif c == "+"
        NET_BRIGHT
      else
        OFF
      end
    end

    private

    def draw_logo
      y = 1
      while y <= LedMatrix::HEIGHT
        x = 1
        while x <= LedMatrix::WIDTH
          brightness = background_at(x, y)
          @matrix.set(x, y, brightness) unless brightness == OFF
          x += 1
        end
        y += 1
      end
    end
  end

  class GameCourt < Court
    def initialize(matrix)
      super(matrix, top: 1, bottom: LedMatrix::HEIGHT, left: 2, right: LedMatrix::WIDTH - 1)
    end

    def draw
      @matrix.clear
      draw_net
    end

    def background_at(x, y)
      if x == NET_X && y.even?
        NET_BRIGHT
      else
        OFF
      end
    end

    private

    def draw_net
      y = @top
      while y <= @bottom
        @matrix.set(NET_X, y, background_at(NET_X, y))
        y += 1
      end
    end
  end
end
