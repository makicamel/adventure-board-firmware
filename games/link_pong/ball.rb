module LinkPong
  class Ball
    ON            = 0x40
    SMASH_BRIGHT  = 0x80
    HALO_BRIGHT   = 0x20                 # スマッシュした球の上下左右
    HALO_OFFSETS  = [[-1, 0], [1, 0], [0, -1], [0, 1]]
    X_STEPS_PER_Y = 2                    # 大きいほど角度が浅い
    FAST_MS       = 55                   # 打ち返した直後は 55ms で 1 ドット進む
    SMASH_MS      = 35
    SMASH_SPEEDUP_MS = 5                 # スマッシュをスマッシュで返すたびに縮める長さ
    FASTEST_MS    = 20
    SLOW_MS       = 80                   # 減速しきると 80ms で 1 ドット進む
    SLOWDOWN_MS   = 2                    # 1 フレームごとの減速
    MISS_BLINKS   = 3

    attr_reader :x, :y, :dx, :interval    # interval は次のフレームまでの長さ
    attr_reader :smash_chain              # スマッシュが何回続いたか。最初のスマッシュは 0

    def self.serve(court)
      y = court.top + 2 + rand(court.bottom - court.top - 3)
      new(court, court.left, y, 1, rand(2) == 0 ? -1 : 1)
    end

    def initialize(court, x, y, dx, dy)
      @court = court
      @x = x
      @y = y
      @dx = dx
      @dy = dy
      @frames = 0
      @interval = FAST_MS
      @smashed = false
      @smash_chain = 0
      @halo_on_screen = false
      @bounced = false
    end

    def will_hit_wall?
      (@frames + 1) % X_STEPS_PER_Y == 0 && (@y + @dy < @court.top || @court.bottom < @y + @dy)
    end

    def bounce
      turn_back(FAST_MS, false)
    end

    def smash
      @smash_chain = @smashed ? @smash_chain + 1 : 0
      turn_back([SMASH_MS - SMASH_SPEEDUP_MS * @smash_chain, FASTEST_MS].max, true)
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

    # ボールが column の列のパドルの前に着くまでのフレーム数
    def frames_until(column)
      (column - @dx - @x).abs
    end

    # ボールが column の列のパドルの前に着くときの y
    def y_at(column)
      goal = column - @dx
      x = @x
      y = @y
      dy = @dy
      frames = @frames
      while short_of?(goal, x)
        x += @dx
        frames += 1
        if frames % X_STEPS_PER_Y == 0
          dy = -dy if y + dy < @court.top || @court.bottom < y + dy
          y += dy
        end
      end
      y
    end

    def redraw = draw

    def blink
      i = 0
      while i < MISS_BLINKS * 2
        @court.set(@x, @y, i % 2 == 0 ? ON : Court::OFF)
        @court.flush
        sleep_ms 200
        i += 1
      end
    end

    private

    def short_of?(goal, x) = (goal - x) * @dx > 0

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
