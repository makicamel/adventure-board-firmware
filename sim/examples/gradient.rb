# 左から右へ暗→明のグラデーション。PWM がそのまま明るさに効く。

# require したファイルは、コンパイラをヒープに残していく。
# 1 本読むたびに GC で片付けないと、次が読めなくなる。
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/led_matrix'
GC.start

matrix.clear
y = 1
while y <= 16
  x = 1
  while x <= 16
    matrix.set(x, y, x * 16 - 1)
    x += 1
  end
  y += 1
end
matrix.show
