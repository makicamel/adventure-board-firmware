# 外周の枠と対角線。向きと縦横の入れ替わりが一目で分かる。

require 'picorubykaigi01'
require 'picorubykaigi01/led_matrix'

matrix.clear

i = 1
while i <= 16
  matrix.set(i, 1)
  matrix.set(i, 16)
  matrix.set(1, i)
  matrix.set(16, i)
  matrix.set(i, i, 0x60)
  i += 1
end

# 左上だけ明るくして向きの目印にする。
matrix.set(2, 2, 0xFF)
matrix.set(3, 2, 0xFF)
matrix.set(2, 3, 0xFF)

matrix.show
