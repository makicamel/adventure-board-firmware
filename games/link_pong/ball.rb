module LinkPong
  class Ball
    ON            = 0x40
    SMASH_BRIGHT  = 0x80
    HALO_BRIGHT   = 0x20                 # スマッシュした球の上下左右
    HALO_OFFSETS  = [[-1, 0], [1, 0], [0, -1], [0, 1]]
    X_STEPS_PER_Y = 2                    # 大きいほど角度が浅い
    FAST_MS       = 55                   # 打ち返した直後は 55ms で 1 ドット進む
    SMASH_MS      = 35
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
      @smashed = false
      @halo_on_screen = false
      @bounced = false
    end

    def will_go_out?
      @x + @dx < @court.left || @court.right < @x + @dx
    end

    def will_hit_wall?
      (@frames + 1) % X_STEPS_PER_Y == 0 && (@y + @dy < @court.top || @court.bottom < @y + @dy)
    end

    def bounce
      turn_back(FAST_MS, false)
    end

    def smash
      turn_back(SMASH_MS, true)
    end

    def out?
      @x < @court.left || @court.right < @x
    end

    def move
      erase
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
      draw
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

    private

    def turn_back(interval, smashed)
      @dx = -@dx
      @interval = interval
      @smashed = smashed
      @bounced = true
    end

    def erase
      @court.redraw_background(@x, @y)
      erase_halo if @halo_on_screen
    end

    def draw
      draw_halo if @smashed
      @halo_on_screen = @smashed
      @court.set(@x, @y, @smashed ? SMASH_BRIGHT : ON)
    end

    def draw_halo
      HALO_OFFSETS.each do |dx, dy|
        x = @x + dx
        y = @y + dy
        @court.set(x, y, HALO_BRIGHT) if inside_court?(x, y)
      end
    end

    def erase_halo
      HALO_OFFSETS.each do |dx, dy|
        x = @x + dx
        y = @y + dy
        @court.redraw_background(x, y) if inside_court?(x, y)
      end
    end

    def inside_court?(x, y)
      @court.left <= x && x <= @court.right && @court.top <= y && y <= @court.bottom
    end
  end
end
