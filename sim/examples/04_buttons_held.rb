# チュートリアル 4: A を押しているあいだだけ光らせる。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを回収する

matrix = AdventureBoard.matrix         # LED マトリクス。使う部品は、こうして読み込んで取り出す
buttons = AdventureBoard.buttons       # ボタン

while true
  if buttons.pressed?(:a)   # A を押しているあいだ
    matrix.fill(0x40)       # 全部を暗く光らせる
  else
    matrix.clear
  end
  matrix.show
  sleep_ms 30
end
