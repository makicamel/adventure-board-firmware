require 'adventure_board'
GC.start

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

  class Ball
    BRIGHT        = 0xFF
    X_STEPS_PER_Y = 2                    # 大きいほど角度が浅い
    FAST_MS       = 55                   # 打ち返した直後は 55ms で 1 ドット進む
    SLOW_MS       = 80                   # 減速しきると 80ms で 1 ドット進む
    SLOWDOWN_MS   = 2                    # 1 フレームごとの減速

    attr_reader :x, :y, :dx, :interval    # interval は次のフレームまでの長さ

    def initialize(court, x, y, dx, dy)
      @court = court
      @x = x
      @y = y
      @dx = dx
      @dy = dy
      @tick = 0
      @interval = FAST_MS
      @bounced = false
    end

    def will_go_out?
      @x + @dx < @court.left || @court.right < @x + @dx
    end

    # パドルが受けたときに呼ぶ。呼ばれなければ、ボールはそのままコートの外へ出る
    def bounce
      @dx = -@dx
      @interval = FAST_MS
      @bounced = true
    end

    def out?
      @x < @court.left || @court.right < @x
    end

    def move
      @court.restore(@x, @y)
      if @bounced
        @bounced = false
      elsif @interval < SLOW_MS
        @interval += SLOWDOWN_MS
      end
      @x += @dx
      @tick += 1
      if @tick % X_STEPS_PER_Y == 0
        @dy = -@dy if @y + @dy < @court.top || @court.bottom < @y + @dy
        @y += @dy
      end
      @court.set(@x, @y, BRIGHT)
    end

    # ボールが受ける側のパドルの前に来るときの y を先回りして求める。タイトル用
    def landing_y
      goal = @dx < 0 ? @court.left : @court.right
      x = @x
      y = @y
      dy = @dy
      tick = @tick
      while x != goal
        x += @dx
        tick += 1
        if tick % X_STEPS_PER_Y == 0
          dy = -dy if y + dy < @court.top || @court.bottom < y + dy
          y += dy
        end
      end
      y
    end
  end

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

  # ボールを受ける側のパドルだけが動き、打ち返したら相手の番になる
  class Title
    def initialize(matrix)
      @court = TitleCourt.new(matrix)
      @court.draw
      @left = Paddle.new(@court, @court.left - 1, @court.top + 1)
      @right = Paddle.new(@court, @court.right + 1, @court.top + 1)
      serve
      @court.flush
    end

    # 次のフレームの時刻を時計で決めるので、ビルドで速さが変わらない
    def run
      next_at = Machine.uptime_us / 1000
      while true
        if next_at <= Machine.uptime_us / 1000
          if @ball.will_go_out? && receiver.covers?(@ball.y)
            @ball.bounce
            receiver.aim(@ball.landing_y)  # 打ち返したので、相手のパドルの番
          end
          @ball.move
          if @ball.out?                  # 受けそこねた。ゲームではここがゲームオーバー
            @court.restore(@ball.x, @ball.y)
            serve
          end
          receiver.step
          @court.flush
          next_at += @ball.interval
        end
        sleep_ms 10
      end
    end

    private

    def serve
      @ball = Ball.new(@court, @court.left, @court.top, 1, 1)
      receiver.aim(@ball.landing_y)
    end

    def receiver
      @ball.dx < 0 ? @left : @right
    end
  end
end

matrix = AdventureBoard.matrix
LinkPong::Title.new(matrix).run
