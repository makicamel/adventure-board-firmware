# チュートリアル 3: 漢字を 1 文字出す。

require 'adventure_board'
GC.start

matrix = AdventureBoard.matrix

matrix.clear_drawing
matrix.draw_text("冒")
matrix.blit
matrix.show
