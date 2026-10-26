module LinkPong
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
