# L 字を描く。上半分と下半分（別々の LED ドライバ）をまたいで真っ直ぐに見えるか。

require 'adventure_board/led_matrix'   # LED マトリクス
GC.start                               # 読み込みで使ったメモリを片付ける

matrix = AdventureBoard.matrix

matrix.clear

y = 2
while y <= 14          # 縦の線。8 行目と 9 行目の間でドライバが替わる
  matrix.set(3, y)
  y += 1
end

x = 4
while x <= 10          # 横の線
  matrix.set(x, 14)
  x += 1
end

matrix.show
