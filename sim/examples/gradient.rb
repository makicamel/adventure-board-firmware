# 左から右へ、暗い → 明るいのグラデーション。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを片付ける

matrix = AdventureBoard.matrix         # LED マトリクス。使う部品は、こうして読み込んで取り出す

matrix.clear
y = 1
while y <= 16
  x = 1
  while x <= 16
    matrix.set(x, y, x * 16 - 1)   # 明るさ 15, 31, ... 255。見た目に比例するよう補正される
    x += 1
  end
  y += 1
end
matrix.show
