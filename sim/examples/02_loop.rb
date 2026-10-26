# チュートリアル 2: 点を左から右へ動かす。

require 'adventure_board'
GC.start

matrix = AdventureBoard.matrix

x = 1
while true
  matrix.clear
  matrix.set(x, 8)
  matrix.show

  x += 1
  x = 1 if 16 < x   # 右端まで行ったら左端へ戻す
  sleep_ms 100      # 0.1 秒待つ
end
