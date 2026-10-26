# チュートリアル 2: 跳ねるボール。端に来たら向きを変える。

require 'adventure_board'
GC.start

matrix = AdventureBoard.matrix

x = 1
y = 5
dx = 1    # 1 回に x がどれだけ動くか
dy = 1    # 1 回に y がどれだけ動くか

while true
  matrix.clear
  matrix.set(x, y)
  matrix.show

  x += dx
  y += dy
  dx = -dx if x <= 1 || 16 <= x   # 左右の端に来たら向きを変える
  dy = -dy if y <= 1 || 16 <= y   # 上下の端に来たら向きを変える
  sleep_ms 60
end
