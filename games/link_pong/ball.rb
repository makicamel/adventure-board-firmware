module LinkPong
  class Ball
    ON            = 0x40
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
      @frames = 0
      @interval = FAST_MS
      @bounced = false
    end

    def will_go_out?
      @x + @dx < @court.left || @court.right < @x + @dx
    end

    def bounce
      @dx = -@dx
      @interval = FAST_MS
      @bounced = true
    end

    def out?
      @x < @court.left || @court.right < @x
    end

    def move
      @court.redraw_background(@x, @y)
      if @bounced
        @bounced = false
      elsif @interval < SLOW_MS
        @interval += SLOWDOWN_MS
      end
      @x += @dx
      @frames += 1
      if @frames % X_STEPS_PER_Y == 0
        @dy = -@dy if @y + @dy < @court.top || @court.bottom < @y + @dy
        @y += @dy
      end
      @court.set(@x, @y, ON)
    end

    def y_at_receiving_paddle
      goal = @dx < 0 ? @court.left : @court.right
      x = @x
      y = @y
      dy = @dy
      frames = @frames
      while x != goal
        x += @dx
        frames += 1
        if frames % X_STEPS_PER_Y == 0
          dy = -dy if y + dy < @court.top || @court.bottom < y + dy
          y += dy
        end
      end
      y
    end
  end
end
