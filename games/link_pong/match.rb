module LinkPong
  # GROVE でつないだ 2 枚の基板で 1 つのコートを作って打ち合う。先に待っていたほうが左
  #
  # 基板間で送るメッセージ（1 行。単語はスペース区切り）
  #   join                                                         2P を選んで待ち始めた
  #   start sideways                                               試合の申し込み。sideways はパドルが左右にも動くなら 1、上下だけなら 0
  #   ok                                                           申し込みを受け入れた
  #   ball y dy frames interval smashed smash_chain rally_length   ボールを渡す。smashed はスマッシュした球なら 1、ふつうの球なら 0
  #   miss rally_length                                            打ち返せなかった
  class Match
    BALL_ON_PARTNER_SIDE_FRAME_MS = Ball::FAST_MS
    BALL_RETURN_TIMEOUT_MS        = 5000

    include Screen
    include Controls

    def initialize(matrix, buttons, sound, link, chosen_sideways)
      @matrix = matrix
      @buttons = buttons
      @sound = sound
      @link = link
      @chosen_sideways = chosen_sideways
    end

    def run
      agreement = agree_with_partner
      return nil unless agreement # 接続前にボタンが押されたらタイトルに戻る

      left, game_sideways = agreement
      start(left, game_sideways)
      play
    end

    private

    # @return [Array(Boolean, Boolean)] [左かどうか, パドルが左右にも動くか]。左右に動くかは、先に選択したプレイヤー（左）の選択
    # @return [nil] つながる前にボタンが押された場合nil
    def agree_with_partner
      @link.flush  # 前の試合やメニューの間に届いたstartやokで試合を始めないように捨てる
      @buttons.clear_presses
      draw_waiting
      @link.write("join")
      sent_start = false
      while true
        return nil if @buttons.take_press

        message = @link.read
        if message && message[0] == "join"  # 相手が来たら試合を申し込む
          @link.write("start", @chosen_sideways ? 1 : 0)
          sent_start = true
        elsif message && message[0] == "start" && !(sent_start && @link.role_a?)  # 申し込みを受けて右になる。abが同時に申し込んだ場合、bが申し込みを受けて右に、aは無視してokを待ち左になる
          @link.write("ok")
          return [false, message[1] == "1"]
        elsif message && message[0] == "ok"  # 申し込みが受け入れられたら左になる
          return [true, @chosen_sideways]
        end
        sleep_ms 10
      end
    end

    def draw_waiting
      repaint { draw_centered_text("2P", Paddle::ON) }
    end

    def start(left, game_sideways)
      @mirrored = !left
      @court = LinkCourt.new(@mirrored ? MirroredMatrix.new(@matrix) : @matrix)
      @court.draw
      @player = Paddle.new(@court, @court.left - 1, @court.middle, columns: @court.left_columns(game_sideways))
      @ball = left ? Ball.serve(@court) : nil
      @rally_length = 0
      @buttons.clear_presses
      @court.flush
      @next_at = now_ms
      @passed_at = now_ms
    end

    def play
      while true
        message = @link.read
        if message && message[0] == "ball"  # ボールが自陣に入ってきた
          receive_ball(message)
        elsif message && message[0] == "miss"  # 相手が打ち返せなかったら試合を終える
          @sound.miss
          return message[1].to_i
        end
        return nil if partner_lost?

        if @next_at <= now_ms
          pass_ball if @ball && @ball.leaving?
          tick
          if @ball && @ball.out?
            @link.write("miss", @rally_length)
            @sound.miss
            @ball.blink
            return @rally_length
          end
          @court.flush
          @next_at += @ball ? @ball.interval : BALL_ON_PARTNER_SIDE_FRAME_MS
        end
        sleep_ms 10
      end
    end

    def partner_lost?
      @ball.nil? && BALL_RETURN_TIMEOUT_MS < now_ms - @passed_at
    end

    def tick
      dx, dy = player_direction
      dx = -dx if @mirrored
      if @player.movable?(dx, dy)
        @player.move(dx, dy)
        @sound.move
      end
      if @ball
        if @ball.dx < 0 && @player.meets?(@ball)
          @rally_length += 1
          if @player.middle_at?(@ball.y)
            @ball.smash
            @sound.smash(@ball.smash_chain)
          else
            @ball.bounce
            @sound.hit
          end
        end
        @sound.wall if @ball.will_hit_wall?
        @ball.move
        @ball.redraw
      end
      @player.redraw
      @sound.tick
    end

    def pass_ball
      @link.write("ball", @ball.y, @ball.dy, @ball.frames, @ball.interval, @ball.smashed? ? 1 : 0, @ball.smash_chain, @rally_length)
      @ball.erase
      @ball = nil
      @passed_at = now_ms
    end

    def receive_ball(message)
      y, dy, frames, interval, smashed, smash_chain, rally_length = message[1, 7].map { |word| word.to_i }
      @ball = Ball.new(@court, @court.right + 1, y, -1, dy, frames: frames, interval: interval, smashed: smashed == 1, smash_chain: smash_chain)
      @rally_length = rally_length
      @next_at = now_ms
    end

    def now_ms = Machine.uptime_us / 1000
  end
end
