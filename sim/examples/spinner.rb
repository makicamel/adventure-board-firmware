# 何も押さなくても動き続ける。繰り返しは while true と sleep_ms で書く。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを片付ける
require 'adventure_board/led_matrix'   # LED マトリクス
GC.start

t = 0                   # 何周目か

while true
  t += 1
  matrix.clear

  i = t % 60            # 外周を 60 歩で 1 周する点
  if i < 16
    matrix.set(i + 1, 1)                # 上の辺を右へ
  elsif i < 30
    matrix.set(16, i - 14)              # 右の辺を下へ
  elsif i < 45
    matrix.set(16 - (i - 30), 16)       # 下の辺を左へ
  else
    matrix.set(1, 16 - (i - 45))        # 左の辺を上へ
  end

  w = (t % 16) + 1      # 中央のバーの長さ（1〜16）
  x = 1
  while x <= w
    matrix.set(x, 8, 0x30)
    x += 1
  end

  matrix.show
  sleep_ms 80           # 待っているあいだ、ほかの処理に順番が回る
end
