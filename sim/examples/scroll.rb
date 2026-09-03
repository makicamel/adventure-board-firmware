# 文字を右から左へ流す。

# require したファイルは、コンパイラをヒープに残していく。
# 1 本読むたびに GC で片付けないと、次が読めなくなる。
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/led_matrix'
GC.start

text = "PicoRubyKaigi 第一回 ようこそ"
x = 16

# 文字の明るさ。draw_text は色を取らないので、pen で決める。
matrix.pen = 0xC0

while true
  matrix.clear_drawing
  matrix.draw_text(text, x, 0)
  matrix.blit
  matrix.show

  x -= 1
  # 全部流れ切ったら右端へ戻す。全角 1 文字 16px の概算。
  x = 16 if x < -(text.size * 16)

  sleep_ms 90
end
