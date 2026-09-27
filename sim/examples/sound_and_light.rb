# メロディを 1 音ずつ鳴らし、音の高さを棒グラフにして流す。
# 音と光を同じループで進めるので、ずれない。鳴り始めが一番明るく、音が伸びるあいだに暗くなる。

require 'adventure_board/led_matrix'   # LED マトリクス
GC.start                               # 読み込みで使ったメモリを片付ける
require 'adventure_board/speaker'      # スピーカー
GC.start

matrix = AdventureBoard.matrix         # ライブラリから使う部品を取り出す
speaker = AdventureBoard.speaker

UNIT_MS = 40   # STEPS の 1 単位の長さ。小さくすると速くなる

# 「歓喜の歌」。NOTES は音の番号（60 がド、1 増えると半音上。nil は休符）、STEPS はその長さ（8 で 4 分音符）
NOTES = [64, 64, 65, 67,  67, 65, 64, 62,  60, 60, 62, 64,  64, 62, 62, nil]
STEPS = [ 8,  8,  8,  8,   8,  8,  8,  8,   8,  8,  8,  8,  12,  4, 16,   8]

# x 列目に、下から height 個の棒を明るさ level で描く。
# def の中からは外の変数（matrix）が見えないので、引数で受け取る
def draw_bar(matrix, x, height, level)
  return if height <= 0
  matrix.draw_rect(x - 1, 16 - height, 1, height, level)   # 描画用のメモリ（VRAM）に四角を 1 つ。座標は 0〜15
end

speaker.reset                    # 前のプログラムが残した音量や音色の設定を初期値に戻す

heights = Array.new(16, 0)       # 16 列ぶんの棒の高さ。右端が今の音
i = 0

while true
  note = NOTES[i]
  steps = STEPS[i]

  heights.shift                                  # 全体を左へ 1 列ずらして
  heights << (note ? (note - 59) * 2 : 0)        # 右端に今の音の高さを足す（ド=2 … ソ=16、休符=0）

  matrix.clear_drawing                           # 過ぎた音の棒は音ごとに 1 回だけ描く
  x = 1
  while x <= 15
    draw_bar(matrix, x, heights[x - 1], 0x20)            # 過ぎた音は暗く
    x += 1
  end

  speaker.note_on(note) if note                  # 鳴らす

  total = steps * UNIT_MS                        # この音の長さ（ms）
  started = Machine.uptime_us / 1000
  sounding = !note.nil?
  while (elapsed = Machine.uptime_us / 1000 - started) < total   # 時計で測るので、基板でもシミュレータでも同じ速さ
    matrix.draw_rect(15, 0, 1, 16, 0)            # 右端の列を消して
    draw_bar(matrix, 16, heights[15], 0xFF - 0xC0 * elapsed / total)   # 今の音の棒。だんだん暗く
    matrix.blit                                  # VRAM の内容をマトリクスへ写す（1 ドットずつ set するより速い）
    matrix.show
    if sounding && total - UNIT_MS <= elapsed    # 最後の 1 単位は音を止めて、次の音と区切る
      speaker.note_off(note)
      sounding = false
    end
    sleep_ms 10
  end

  i = (i + 1) % NOTES.size                       # 最後まで行ったら最初へ
end
