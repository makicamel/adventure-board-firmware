# 左上の 1 個だけ光らせる。

require 'picorubykaigi01'
require 'picorubykaigi01/led_matrix'

matrix.clear
matrix.set(1, 1)
matrix.show
