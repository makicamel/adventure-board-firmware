module LinkPong
  class Game
    MISS_BLINKS = 3
    HELD_DOTS   = 2                      # 上下を押し続けたとき 1 フレームに動くドット数

    def initialize(matrix, buttons, sound, sideways)
      @buttons = buttons
      @sound = sound
      @buttons.clear_presses
      @court = GameCourt.new(matrix)
      @court.draw
      @player = Paddle.new(
        @court, @court.left - 1, @court.middle,
        columns: @court.left_columns(sideways),
      )
      @cpu = AutoPaddle.new(
        @court, @court.right + 1, @court.middle,
        columns: @court.right_columns(sideways),
        frames_per_dot: 1,
      )
      @ball = new_ball
      @cpu.receive(@ball, offset: cpu_offset)
      @returns = 0
      @court.flush
    end

    def run
      next_at = Machine.uptime_us / 1000
      while true
        if next_at <= Machine.uptime_us / 1000
          tick
          if @ball.out?
            @sound.miss
            show_miss
            return @returns
          end
          @court.flush
          next_at += @ball.interval
        end
        sleep_ms 10
      end
    end

    private

    def new_ball
      y = @court.top + 2 + rand(@court.bottom - @court.top - 3)
      Ball.new(@court, @court.left, y, 1, rand(2) == 0 ? -1 : 1)
    end

    # CPU がパドルのどこで受けるか。真ん中ならスマッシュになる
    def cpu_offset
      rand(Paddle::HALF_LENGTH * 2 + 1) - Paddle::HALF_LENGTH
    end

    def tick
      dx, dy = player_direction
      if @player.movable?(dx, dy)
        @player.move(dx, dy)
        @sound.move
      end
      if receiver.meets?(@ball)
        hitter = receiver
        @returns += 1 if hitter.equal?(@player)
        if receiver.middle_at?(@ball.y)
          @ball.smash
          @sound.smash(@ball.smash_chain)
        else
          @ball.bounce
          @sound.hit
        end
        if hitter.equal?(@player)
          @cpu.receive(@ball, offset: cpu_offset)
        else
          @cpu.drift(@ball)
        end
      end
      @sound.wall if @ball.will_hit_wall?
      @ball.move
      @cpu.tick
      @ball.redraw
      @player.redraw
      @cpu.redraw
      @sound.tick
    end

    # 短く押したのも取りこぼさないように、押した回数（each_press）を先に見る
    def player_direction
      pressed_dx = 0
      pressed_dy = 0
      @buttons.each_press do |name|
        pressed_dx = -1 if name == :left
        pressed_dx = 1 if name == :right
        pressed_dy = -1 if name == :up
        pressed_dy = 1 if name == :down
      end
      dx = pressed_dx == 0 ? held_direction(:left, :right) : pressed_dx
      dy = pressed_dy == 0 ? held_direction(:up, :down) * HELD_DOTS : pressed_dy
      [dx, dy]
    end

    def held_direction(minus, plus)
      if @buttons.pressed?(minus)
        -1
      elsif @buttons.pressed?(plus)
        1
      else
        0
      end
    end

    def receiver
      @ball.dx < 0 ? @player : @cpu
    end

    def show_miss
      i = 0
      while i < MISS_BLINKS * 2
        @court.set(@ball.x, @ball.y, i % 2 == 0 ? Ball::ON : Court::OFF)
        @court.flush
        sleep_ms 200
        i += 1
      end
    end
  end
end
