# チュートリアル 1: 場所と明るさを変えて、4 つ光らせる。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを回収する

matrix = AdventureBoard.matrix         # LED マトリクス。使う部品は、こうして読み込んで取り出す

matrix.clear
matrix.set(1, 1)          # 左上
matrix.set(16, 1)         # 右上
matrix.set(8, 8, 0x20)    # まんなかを暗く
matrix.set(16, 16, 0xFF)  # 右下をいちばん明るく
matrix.show
