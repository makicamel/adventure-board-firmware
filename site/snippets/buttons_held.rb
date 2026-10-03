require 'adventure_board'
GC.start

matrix = AdventureBoard.matrix
buttons = AdventureBoard.buttons

while true
  if buttons.pressed?(:a)   # A を押しているあいだ
    matrix.fill(0x40)       # 全部を暗く光らせる
  else
    matrix.clear
  end
  matrix.show
  sleep_ms 30
end
