# 左上の 1 個だけ光らせる。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを片付ける

matrix = AdventureBoard.matrix         # LED マトリクス。使う部品は、こうして読み込んで取り出す

matrix.clear       # 全部消す
matrix.set(1, 1)   # x=1, y=1（左上）を点ける。座標は 1〜16
matrix.show        # ここで初めて LED に反映される
