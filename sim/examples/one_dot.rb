# 左上の 1 個だけ光らせる。

# require したファイルは、コンパイラをヒープに残していく。
# 1 本読むたびに GC で片付けないと、次が読めなくなる。
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/led_matrix'
GC.start

matrix.clear
matrix.set(1, 1)
matrix.show
