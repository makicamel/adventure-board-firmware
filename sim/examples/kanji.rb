# 漢字を出す。16×16 を選んだ理由そのもの。
#
# picoruby-shinonome の JIS 16×16 ビットマップフォントが、
# このマトリクスにちょうど収まる。
#
# ※ このサンプルは `rake sim:wasm` でビルドしたローカルの PicoRuby.wasm が
#    必要。CDN の stock パッケージにはフォントの gem が入っていない。

# require したファイルは、コンパイラをヒープに残していく。
# 1 本読むたびに GC で片付けないと、次が読めなくなる。
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/led_matrix'
GC.start

matrix.clear
matrix.clear_drawing
matrix.draw_text("宝")
matrix.blit
matrix.show
