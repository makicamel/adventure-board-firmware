module LinkPong
  class Game
    include Controls

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
      @ball = Ball.serve(@court)
      @cpu.receive(@ball, offset: AutoPaddle.random_offset)
      @rally_length = 0
      @court.flush
    end

    def run
      next_at = Machine.uptime_us / 1000
      while true
        if next_at <= Machine.uptime_us / 1000
          tick
          if @ball.out?
            @sound.miss
            @ball.blink
            return @rally_length
          end
          @court.flush
          next_at += @ball.interval
        end
        sleep_ms 10
      end
    end

    private

    def tick
      dx, dy = player_direction
      if @player.movable?(dx, dy)
        @player.move(dx, dy)
        @sound.move
      end
      if receiver.meets?(@ball)
        hitter = receiver
        @rally_length += 1 if hitter.equal?(@player)
        if receiver.middle_at?(@ball.y)
          @ball.smash
          @sound.smash(@ball.smash_chain)
        else
          @ball.bounce
          @sound.hit
        end
        if hitter.equal?(@player)
          @cpu.receive(@ball, offset: AutoPaddle.random_offset)
        else
          @cpu.wander(@ball)
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

    def receiver
      @ball.dx < 0 ? @player : @cpu
    end
  end
end
