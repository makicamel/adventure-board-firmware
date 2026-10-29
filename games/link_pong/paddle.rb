module LinkPong
  class Paddle
    ON          = 0x40
    HALF_LENGTH = 1

    attr_reader :x

    # columns は横に動ける範囲。渡さなければ x から動かない
    def initialize(court, x, middle, columns: x..x)
      @court = court
      @x = x
      @middle = middle
      @columns = columns
      draw
    end

    # 次のフレームでボールがパドルの列に入るか、パドルがボールの列に来ていて、高さが合っている
    def meets?(ball)
      (ball.x + ball.dx == @x || ball.x == @x) && covers?(ball.y)
    end

    def covers?(y)
      @middle - HALF_LENGTH <= y && y <= @middle + HALF_LENGTH
    end

    def middle_at?(y)
      @middle == y
    end

    def movable?(dx, dy)
      clamp_x(@x + dx) != @x || clamp_y(@middle + dy) != @middle
    end

    def move(dx, dy)
      return unless movable?(dx, dy)
      erase
      @x = clamp_x(@x + dx)
      @middle = clamp_y(@middle + dy)
      draw
    end

    # ボールや周りの光に消されても戻るように、毎フレーム描き直す
    def redraw = draw

    private

    def draw
      y = @middle - HALF_LENGTH
      while y <= @middle + HALF_LENGTH
        @court.set(@x, y, ON)
        y += 1
      end
    end

    def erase
      y = @middle - HALF_LENGTH
      while y <= @middle + HALF_LENGTH
        @court.redraw_background(@x, y)
        y += 1
      end
    end

    def clamp_x(x)
      if x < @columns.first
        @columns.first
      elsif @columns.last < x
        @columns.last
      else
        x
      end
    end

    # パドルの真ん中の y を収める
    def clamp_y(middle)
      if middle < highest_middle
        highest_middle
      elsif lowest_middle < middle
        lowest_middle
      else
        middle
      end
    end

    def highest_middle = @court.top + HALF_LENGTH

    def lowest_middle = @court.bottom - HALF_LENGTH

    def reachable?(middle)
      highest_middle <= middle && middle <= lowest_middle
    end
  end

  class AutoPaddle < Paddle
    FRAMES_PER_DOT = 2

    # パドルのどこで受けるか。真ん中ならスマッシュになる
    def self.random_offset
      rand(Paddle::HALF_LENGTH * 2 + 1) - Paddle::HALF_LENGTH
    end

    def initialize(court, x, middle, columns: x..x, frames_per_dot: FRAMES_PER_DOT)
      super(court, x, middle, columns: columns)
      @home = x
      @frames_per_dot = frames_per_dot
      @target_x = x
      @waypoints = []
      @following = nil
      @frames = 0
    end

    # 向かってくるボールを受けに行く。いまの列から元の列までのうち、間に合ういちばん近い列で受ける
    def receive(ball, offset: 0)
      column = receiving_column(ball, offset)
      target = clamp_y(ball.y_at(column) + offset)
      frames = ball.frames_until(column)
      overshoot = @middle < target ? target + 1 : target - 1
      @waypoints = reachable?(overshoot) && in_time?(column, target, frames, 2) ? [overshoot, target] : [target]
      @target_x = column
      @following = nil
      @frames = 0
    end

    # ボールが遠ざかっているあいだに、自分の側のどこかの列へ移り、高さはボールに合わせておく
    def wander(ball)
      @target_x = @columns.first + rand(@columns.last - @columns.first + 1)
      @waypoints = []
      @following = ball
    end

    def tick
      @frames += 1
      return unless @frames % @frames_per_dot == 0
      goal = @following ? clamp_y(@following.y) : @waypoints[0]
      dx = @target_x <=> @x
      dy = goal.nil? ? 0 : goal <=> @middle
      move(dx, dy)
      @waypoints.shift if @following.nil? && goal == @middle
    end

    private

    def receiving_column(ball, offset)
      step = @home <=> @x
      column = @x
      until column == @home
        return column if in_time?(column, clamp_y(ball.y_at(column) + offset), ball.frames_until(column), 0)
        column += step
      end
      @home
    end

    # 横と縦は同時に動けるので、かかるのは遠いほうのドット数
    def in_time?(column, target, frames, extra)
      steps = [(column - @x).abs, (target - @middle).abs + extra].max
      steps * @frames_per_dot <= frames
    end
  end
end
