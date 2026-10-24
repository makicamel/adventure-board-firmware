# チュートリアル 4: 十字ボタンで点を動かす。
# シミュレータでは画面のボタンか、キーボード（矢印キー / Z=A / X=B）。

require 'adventure_board'
GC.start

matrix = AdventureBoard.matrix
buttons = AdventureBoard.buttons

x = 8
y = 8

while true
  buttons.each_press do |name|   # 押されたボタンを 1 つずつ取り出す
    x -= 1 if name == :left
    x += 1 if name == :right
    y -= 1 if name == :up
    y += 1 if name == :down
  end
  x = 1 if x < 1                 # はみ出さないように
  x = 16 if 16 < x
  y = 1 if y < 1
  y = 16 if 16 < y

  matrix.clear
  matrix.set(x, y)
  matrix.show
  sleep_ms 30
end
