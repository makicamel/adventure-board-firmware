# 市松模様。明るいマスと暗いマスを交互に並べる。

require 'picorubykaigi01'
GC.start                               # 読み込みで使ったメモリを片付ける
require 'picorubykaigi01/led_matrix'   # LED マトリクス
GC.start

matrix.clear
y = 1
while y <= 16
  x = 1
  while x <= 16
    matrix.set(x, y, ((x + y) % 2 == 0) ? 0xFF : 0x30)   # 3 番目の引数が明るさ（0〜255）
    x += 1
  end
  y += 1
end
matrix.show
