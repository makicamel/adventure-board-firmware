# 漢字を出す。16×16 を選んだ理由そのもの。
#
# picoruby-shinonome の JIS 16×16 ビットマップフォントが、
# このマトリクスにちょうど収まる。
#
# ※ このサンプルは `rake sim:wasm` でビルドしたローカルの PicoRuby.wasm が
#    必要。CDN の stock パッケージにはフォントの gem が入っていない。

require 'picorubykaigi01'
require 'picorubykaigi01/led_matrix'

matrix.clear
matrix.clear_drawing
matrix.draw_text("宝")
matrix.blit
matrix.show
