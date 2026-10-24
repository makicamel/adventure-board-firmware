# チュートリアル 1: 左上の 1 つだけ光らせる。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを回収する

matrix = AdventureBoard.matrix         # LED マトリクス。使う部品は、こうして読み込んで取り出す

matrix.clear
matrix.set(1, 1)
matrix.show
