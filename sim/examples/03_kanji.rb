# チュートリアル 3: 漢字を 1 文字出す。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを回収する

matrix = AdventureBoard.matrix         # LED マトリクス。使う部品は、こうして読み込んで取り出す

matrix.clear_drawing
matrix.draw_text("冒")
matrix.blit
matrix.show
