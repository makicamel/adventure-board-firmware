module LinkPong
  class Title
    include Screen

    def initialize(matrix, buttons)
      @buttons = buttons
      @buttons.clear_presses
      @court = TitleCourt.new(matrix)
      @court.draw
      @left = AutoPaddle.new(@court, @court.left - 1, @court.top + 1, columns: (@court.left - 1)..(Court::NET_X - 1))
      @right = AutoPaddle.new(@court, @court.right + 1, @court.top + 1, columns: (Court::NET_X + 1)..(@court.right + 1))
      @ball = new_ball
      receiver.receive(@ball)
      @court.flush
    end

    def run
      next_at = Machine.uptime_us / 1000
      while true
        return if any_button_pressed?
        if next_at <= Machine.uptime_us / 1000
          tick
          @court.flush
          next_at += @ball.interval
        end
        sleep_ms 10
      end
    end

    private

    def new_ball
      Ball.new(@court, @court.left, @court.top, 1, 1)
    end

    def receiver
      @ball.dx < 0 ? @left : @right
    end

    def tick
      if receiver.meets?(@ball)
        hitter = receiver
        @ball.bounce
        receiver.receive(@ball)
        hitter.drift(@ball)
      end
      @ball.move
      if @ball.out?
        @court.redraw_background(@ball.x, @ball.y)
        @ball = new_ball
        receiver.receive(@ball)
      end
      @left.tick
      @right.tick
      @ball.redraw
      @left.redraw
      @right.redraw
    end
  end
end
