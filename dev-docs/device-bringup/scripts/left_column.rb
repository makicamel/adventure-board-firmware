# 左端に縦線を 1 本。上から下まで左端に揃っていれば、下半分の配線の左右反転が正しく直されている。

require 'picorubykaigi01'
GC.start                               # 読み込みで使ったメモリを片付ける
require 'picorubykaigi01/led_matrix'   # LED マトリクス
GC.start

matrix.clear
y = 1
while y <= 16
  matrix.set(1, y)   # x=1（左端）の y 行目
  y += 1
end
matrix.show
