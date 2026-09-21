# メロディを 1 音ずつ鳴らし、音の高さを棒グラフにして流す。
# 音と光を同じループで進めるので、ずれない。鳴り始めが一番明るく、音が伸びるあいだに暗くなる。

require 'picorubykaigi01'
GC.start                               # 読み込みで使ったメモリを片付ける
require 'picorubykaigi01/led_matrix'   # LED マトリクス
GC.start
require 'picorubykaigi01/speaker'      # スピーカー
GC.start

STEP_MS = 50   # 時間の最小単位。小さくすると速くなる

# 「歓喜の歌」。NOTES は音の番号（60 がド、1 増えると半音上。nil は休符）、STEPS はその長さ（8 で 4 分音符）
NOTES = [64, 64, 65, 67,  67, 65, 64, 62,  60, 60, 62, 64,  64, 62, 62, nil]
STEPS = [ 8,  8,  8,  8,   8,  8,  8,  8,   8,  8,  8,  8,  12,  4, 16,   8]

def draw_bar(x, height, level)   # x 列目に、下から height 個の棒を明るさ level で描く
  y = 16
  while 16 - height < y
    matrix.set(x, y, level)
    y -= 1
  end
end

speaker.reset                    # 前のプログラムが残した音量や音色の設定を初期値に戻す

heights = Array.new(16, 0)       # 16 列ぶんの棒の高さ。右端が今の音
i = 0

while true
  note = NOTES[i]
  steps = STEPS[i]

  heights.shift                                  # 全体を左へ 1 列ずらして
  heights << (note ? (note - 59) * 2 : 0)        # 右端に今の音の高さを足す（ド=2 … ソ=16、休符=0）

  matrix.clear
  x = 1
  while x <= 15
    draw_bar(x, heights[x - 1], 0x20)            # 過ぎた音は暗く
    x += 1
  end

  speaker.note_on(note) if note                  # 鳴らす

  step = 0
  while step < steps
    draw_bar(16, heights[15], 0xFF - step * 0xC0 / steps)   # 今の音の棒。だんだん暗く
    matrix.show
    speaker.note_off(note) if note && step == steps - 1     # 最後の 1 単位は音を止めて、次の音と区切る
    sleep_ms STEP_MS
    step += 1
  end

  i = (i + 1) % NOTES.size                       # 最後まで行ったら最初へ
end
