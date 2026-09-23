# 漢字を 1 文字出す。16×16 のフォントがこのマトリクスにちょうど収まる。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを片付ける
require 'adventure_board/led_matrix'   # LED マトリクス
GC.start

matrix.clear
matrix.clear_drawing     # 描画用のメモリ（VRAM）を消す
matrix.draw_text("宝")   # VRAM に文字を描く
matrix.blit              # VRAM の内容をマトリクスへ写す
matrix.show              # LED に反映する
