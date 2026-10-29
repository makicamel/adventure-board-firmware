module LinkPong
  class Sound
    HIT_NOTE      = 84                   # パドルで打ち返した音。60 がド
    WALL_NOTE     = 72                   # 上下の壁で跳ねた音
    MOVE_NOTE     = 48                   # プレイヤーがパドルを動かした音
    MOVE_VELOCITY = 40                   # 動かした音は小さく（ほかは 100）
    BEEP_MS       = 40
    SMASH_MML     = "t240 v15 o6 l64 c g > c e g"
    SMASH_RISE    = 2                    # スマッシュが続くたびに上げる半音の数
    MISS_MML      = "t150 o4 l16 c <g e c"
    RESULT_MML    = "t150 o5 l16 c e g > c"
    LOSE_MML      = "t150 o4 l16 g f+ f e8"      # 半音ずつ下がる

    def initialize(speaker)
      @speaker = speaker
      @speaker.reset
      @note = nil
      @off_at = 0
    end

    def hit = beep(HIT_NOTE)

    def smash(chain) = @speaker.play_mml("k+#{chain * SMASH_RISE} #{SMASH_MML}")

    def wall = beep(WALL_NOTE)

    def move = beep(MOVE_NOTE, MOVE_VELOCITY)

    def miss = @speaker.play_mml(MISS_MML)

    def result = @speaker.play_mml(RESULT_MML)

    def lose = @speaker.play_mml(LOSE_MML)

    def stop = @speaker.stop

    # 鳴らし始めてから BEEP_MS 経過した音を止める
    def tick
      return if @note.nil? || Machine.uptime_us / 1000 < @off_at
      @speaker.note_off(@note)
      @note = nil
    end

    private

    def beep(note, velocity = 100)
      @speaker.note_off(@note) unless @note.nil?
      @speaker.note_on(note, velocity: velocity)
      @note = note
      @off_at = Machine.uptime_us / 1000 + BEEP_MS
    end
  end
end
