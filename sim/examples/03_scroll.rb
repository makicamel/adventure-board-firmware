# チュートリアル 3: 文字を右から左へ流す。

require 'adventure_board'
GC.start

matrix = AdventureBoard.matrix

text = "ようこそ PicoRuby"
x = 16                  # 右の外から始める
matrix.pen = 0xC0       # 文字の明るさ

while true
  matrix.clear_drawing
  matrix.draw_text(text, x, 0)
  matrix.blit
  matrix.show

  x -= 1                                   # 1 ドット左へ
  x = 16 if x < -(text.size * 16)          # 流れきったら右へ戻す
  sleep_ms 80
end
