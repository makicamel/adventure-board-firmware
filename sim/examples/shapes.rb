# VRAM の描画 API。線と矩形。
#
# VRAM は 8bit なので、色にそのまま明るさ (0..255) を渡せる。
# 何も指定しなければ matrix.pen の値が使われる。

# require したファイルは、コンパイラをヒープに残していく。
# 1 本読むたびに GC で片付けないと、次が読めなくなる。
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/led_matrix'
GC.start

matrix.clear
matrix.clear_drawing

matrix.draw_rect(0, 0, 16, 16, 0xFF)    # 外枠は明るく
matrix.draw_line(0, 0, 15, 15, 0x60)    # 対角線は暗く
matrix.draw_line(15, 0, 0, 15, 0x20)    # もう一本はもっと暗く

matrix.blit
matrix.show
