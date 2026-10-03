require 'adventure_board'
GC.start

matrix = AdventureBoard.matrix

matrix.clear
matrix.set(1, 1)
matrix.show
