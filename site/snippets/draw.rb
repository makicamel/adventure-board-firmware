require 'adventure_board'
GC.start

matrix = AdventureBoard.matrix

matrix.clear_drawing                    # 描く場所をまっさらにする

matrix.draw_rect(0, 0, 16, 16, 0xFF)    # 四角（x, y, 幅, 高さ, 明るさ）
matrix.draw_line(0, 0, 15, 15, 0x60)    # 線（始まりの x, y, 終わりの x, y, 明るさ）
matrix.draw_line(15, 0, 0, 15, 0x20)

matrix.blit                             # 描いたものを LED に写す
matrix.show
