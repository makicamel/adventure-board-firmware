module LinkPong
  class Court
    attr_reader :top, :bottom, :left, :right

    def initialize(matrix, top:, bottom:, left:, right:)
      @matrix = matrix
      @top = top
      @bottom = bottom
      @left = left
      @right = right
    end

    def set(x, y, v)
      @matrix.set(x, y, v)
    end

    # ボールやパドルが通ったあとを背景に戻す
    def restore(x, y)
      @matrix.set(x, y, background_at(x, y))
    end

    def flush = @matrix.show

    def background_at(x, y) = 0
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
    TEXT_BRIGHT = 0x40
    NET_BRIGHT  = 0x18

    def initialize(matrix)
      super(matrix, top: 6, bottom: 11, left: 2, right: 15)
    end

    def draw
      @matrix.clear
      y = 1
      while y <= LedMatrix::HEIGHT
        x = 1
        while x <= LedMatrix::WIDTH
          v = background_at(x, y)
          @matrix.set(x, y, v) if 0 < v
          x += 1
        end
        y += 1
      end
    end

    def background_at(x, y)
      c = LOGO[y - 1][x - 1]
      if c == "#"
        TEXT_BRIGHT
      elsif c == "+"
        NET_BRIGHT
      else
        0
      end
    end
  end
end
