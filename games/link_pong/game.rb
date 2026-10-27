module LinkPong
  class Game
    MISS_BLINKS     = 3
    CPU_ERRS_ONE_IN = 5
    CPU_ERROR       = Paddle::HALF_LENGTH + 1

    def initialize(matrix, buttons, sound)
      @buttons = buttons
      @sound = sound
      @buttons.clear_presses
      @court = GameCourt.new(matrix)
      @court.draw
      @player = Paddle.new(@court, @court.left - 1, @court.middle)
      @cpu = AutoPaddle.new(@court, @court.right + 1, @court.middle, frames_per_dot: 1)
      @ball = new_ball
      @cpu.head_for(@ball.y_at_receiving_paddle + cpu_error)
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
            return player_won?
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

    def cpu_error
      if rand(CPU_ERRS_ONE_IN) != 0
        rand(Paddle::HALF_LENGTH * 2 + 1) - Paddle::HALF_LENGTH
      elsif rand(2) == 0
        -CPU_ERROR
      else
        CPU_ERROR
      end
    end

    def tick
      dy = player_dy
      if @player.movable?(dy)
        @player.move(dy)
        @sound.move
      end
      if @ball.will_go_out? && receiver.covers?(@ball.y)
        if receiver.middle_at?(@ball.y)
          @ball.smash
          @sound.smash
        else
          @ball.bounce
          @sound.hit
        end
        @cpu.head_for(@ball.y_at_receiving_paddle + cpu_error) if receiver.equal?(@cpu)
      end
      @sound.wall if @ball.will_hit_wall?
      @ball.move
      @cpu.tick
      @sound.tick
    end

    def player_dy
      dy = dy_from_presses
      dy = dy_from_held if dy == 0
      dy
    end

    def dy_from_presses
      dy = 0
      @buttons.each_press do |name|
        dy = -1 if name == :up
        dy = 1 if name == :down
      end
      dy
    end

    def dy_from_held
      if @buttons.pressed?(:up)
        -1
      elsif @buttons.pressed?(:down)
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

    def player_won?
      @court.right < @ball.x
    end
  end
end
