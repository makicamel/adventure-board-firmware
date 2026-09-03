# 左端の縦一列。下半分は列が左右反転して配線されているので、
# ここが左端に真っ直ぐ 1 本に見えれば cs = 17 - x の向きが正しい。
# 下半分だけ右端に出たら反転の向きが逆。

require 'picorubykaigi01'
require 'picorubykaigi01/led_matrix'

matrix.clear
y = 1
while y <= 16
  matrix.set(1, y)
  y += 1
end
matrix.show
