# 外周の枠と対角線。向きが合っているかが一目で分かる。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを片付ける

matrix = AdventureBoard.matrix

matrix.clear

i = 1
while i <= 16
  matrix.set(i, 1)         # 上の辺
  matrix.set(i, 16)        # 下の辺
  matrix.set(1, i)         # 左の辺
  matrix.set(16, i)        # 右の辺
  matrix.set(i, i, 0x60)   # 対角線は少し暗く
  i += 1
end

matrix.set(2, 2, 0xFF)     # 左上の目印（ここが左上に見えれば向きが正しい）
matrix.set(3, 2, 0xFF)
matrix.set(2, 3, 0xFF)

matrix.show
