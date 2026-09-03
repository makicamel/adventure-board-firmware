# 市松模様。PWM を変えて明るさの差も見る。

require 'picorubykaigi01'
require 'picorubykaigi01/led_matrix'

matrix.clear
y = 1
while y <= 16
  x = 1
  while x <= 16
    matrix.set(x, y, ((x + y) % 2 == 0) ? 0xFF : 0x30)
    x += 1
  end
  y += 1
end
matrix.show
