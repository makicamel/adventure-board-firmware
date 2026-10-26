module LinkPong
  class Title
    def initialize(matrix, buttons)
      @buttons = buttons
      @buttons.clear_presses
      @court = TitleCourt.new(matrix)
      @court.draw
      @left = AutoPaddle.new(@court, @court.left - 1, @court.top + 1)
      @right = AutoPaddle.new(@court, @court.right + 1, @court.top + 1)
      @ball = new_ball
      receiver.head_for(@ball.y_at_receiving_paddle)
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

    def any_button_pressed?
      pressed = false
      @buttons.each_press { pressed = true }
      pressed
    end

    def tick
      if @ball.will_go_out? && receiver.covers?(@ball.y)
        @ball.bounce
        receiver.head_for(@ball.y_at_receiving_paddle)
      end
      @ball.move
      if @ball.out?
        @court.redraw_background(@ball.x, @ball.y)
        @ball = new_ball
        receiver.head_for(@ball.y_at_receiving_paddle)
      end
      receiver.tick
    end
  end
end
