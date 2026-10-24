# 線と四角を描く。色の代わりに明るさ（0〜255）を渡す。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを回収する

matrix = AdventureBoard.matrix         # LED マトリクス。使う部品は、こうして読み込んで取り出す

matrix.clear
matrix.clear_drawing                    # 描画用のメモリ（VRAM）を消す。こちらの座標は 0〜15

matrix.draw_rect(0, 0, 16, 16, 0xFF)    # 外枠は明るく（x, y, 幅, 高さ, 明るさ）
matrix.draw_line(0, 0, 15, 15, 0x60)    # 対角線は暗く（始点 x, y, 終点 x, y, 明るさ）
matrix.draw_line(15, 0, 0, 15, 0x20)    # もう一本はもっと暗く

matrix.blit                             # VRAM の内容をマトリクスへ写す
matrix.show
