require 'adventure_board'
GC.start

matrix = AdventureBoard.matrix

matrix.clear
matrix.set(1, 1)          # 左上
matrix.set(16, 1)         # 右上
matrix.set(8, 8, 0x20)    # まんなかを暗く
matrix.set(16, 16, 0xFF)  # 右下をいちばん明るく
matrix.show
