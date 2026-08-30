# チップ境界（8 行目と 9 行目の間）をまたぐ L 字。
# 上下でチップが変わり、下半分は列が左右反転して配線されているので、
# ここが真っ直ぐ縦に見えれば座標変換が正しいことになる。

require 'picorubykaigi01'

matrix.clear

y = 2
while y <= 14
  matrix.set(3, y)
  y += 1
end

x = 4
while x <= 10
  matrix.set(x, 14)
  x += 1
end

matrix.show
