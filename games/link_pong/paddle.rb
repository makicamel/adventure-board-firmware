module LinkPong
  class Paddle
    BRIGHT = 0xFF
    PACE   = 2                           # 何フレームに 1 ドット動くか

    def initialize(court, x, center)
      @court = court
      @x = x
      @center = center
      @path = []                         # タイトルで自動で動かすときの、パドルの真ん中の y 座標。先頭から順に移動し、最後がボールを受ける y
      @tick = 0
      draw(BRIGHT)
    end

    def aim(y)
      target = clamp(y)
      beyond = @center < target ? target + 1 : target - 1   # 来た向きのまま 1 ドット行き過ぎる
      @path = if beyond < highest || lowest < beyond
                [target]                                    # 端では行き過ぎられないので、まっすぐ着く
              else
                [beyond, target]
              end
      @tick = 0
    end

    def covers?(y)
      @center - 1 <= y && y <= @center + 1
    end

    def step
      @tick += 1
      return if @path.empty? || @tick % PACE != 0
      goal = @path[0]
      if goal != @center
        draw(0)
        @center += goal < @center ? -1 : 1
        draw(BRIGHT)
      end
      @path.shift if @center == goal
    end

    private

    # パドルの真ん中がとれる y の範囲（3 ドットがコートに収まる）
    def highest
      @court.top + 1
    end

    def lowest
      @court.bottom - 1
    end

    def clamp(y)
      return highest if y < highest
      return lowest if lowest < y
      y
    end

    def draw(v)
      @court.set(@x, @center - 1, v)
      @court.set(@x, @center, v)
      @court.set(@x, @center + 1, v)
    end
  end
end
