module LinkPong
  # GROVE でつないだ 2 枚の基板で 1 つのコートを作って打ち合う。先に待っていたプレイヤーの左右の選択を採用する
  #
  # 基板間で送るメッセージ（1 行。単語はスペース区切り）
  #   join                                            2P を選んで待ち始めた
  #   start side                                      試合の提案。先に待っていたプレイヤーが、あとから来たプレイヤーの join を受けて送る。side は自分が選択した左右で、L か R
  #   ok                                              提案への同意。あとから来たプレイヤーが返す
  #   ball y dy frames interval smashed smash_chain   ボールを渡す。smashed はスマッシュした球なら 1、ふつうの球なら 0
  #   miss                                            打ち返せなかった
  class Match
    BALL_ON_PARTNER_SIDE_FRAME_MS = Ball::FAST_MS
    BALL_RETURN_TIMEOUT_MS        = 5000

    include Screen
    include Controls

    def initialize(matrix, buttons, sound, link, chosen_left)
      @matrix = matrix
      @buttons = buttons
      @sound = sound
      @link = link
      @chosen_left = chosen_left
    end

    def run
      left = agree_with_partner
      return nil if left.nil? # 接続前にボタンが押されたらタイトルに戻る

      start(left)
      play
    end

    private

    # @return [Boolean] 左かどうか。先に待っていたプレイヤーは選択したとおり、あとから来たプレイヤーはその反対になる
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
        if message && message[0] == "join"  # あとから来た相手の join を受けたら、試合を提案する
          @link.write("start", @chosen_left ? "L" : "R")
          sent_start = true
        elsif message && message[0] == "start" && !(sent_start && @link.role_a?)  # 先に待っていた相手の提案に同意して、相手の左右の反対になる。同時に提案した場合は、b が a の提案に同意し、a は b の提案を無視して ok を待つ
          @link.write("ok")
          return message[1] == "R"
        elsif message && message[0] == "ok"  # 提案に同意されたら、選択したとおりになる
          return @chosen_left
        end
        sleep_ms 10
      end
    end

    def draw_waiting
      repaint { draw_centered_text("2P", Paddle::ON) }
    end

    def start(left)
      @mirrored = !left
      @court = LinkCourt.new(@mirrored ? MirroredMatrix.new(@matrix) : @matrix)
      @court.draw
      @player = Paddle.new(@court, @court.left - 1, @court.middle)
      @ball = left ? Ball.serve(@court) : nil
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
          return :win
        end
        return nil if partner_lost?

        if @next_at <= now_ms
          pass_ball if @ball && @ball.leaving?
          tick
          if @ball && @ball.out?
            @link.write("miss")
            @sound.miss
            @ball.blink
            return :lose
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
      @link.write("ball", @ball.y, @ball.dy, @ball.frames, @ball.interval, @ball.smashed? ? 1 : 0, @ball.smash_chain)
      @ball.erase
      @ball = nil
      @passed_at = now_ms
    end

    def receive_ball(message)
      y, dy, frames, interval, smashed, smash_chain = message[1, 6].map { |word| word.to_i }
      @ball = Ball.new(@court, @court.right + 1, y, -1, dy, frames: frames, interval: interval, smashed: smashed == 1, smash_chain: smash_chain)
      @next_at = now_ms
    end

    def now_ms = Machine.uptime_us / 1000
  end
end
