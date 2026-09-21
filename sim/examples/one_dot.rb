# 左上の 1 個だけ光らせる。

require 'picorubykaigi01'
GC.start                               # 読み込みで使ったメモリを片付ける
require 'picorubykaigi01/led_matrix'   # LED マトリクス
GC.start

matrix.clear       # 全部消す
matrix.set(1, 1)   # x=1, y=1（左上）を点ける。座標は 1〜16
matrix.show        # ここで初めて LED に反映される
