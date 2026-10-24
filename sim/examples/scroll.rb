# 文字を右から左へ流す。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを回収する

matrix = AdventureBoard.matrix         # LED マトリクス。使う部品は、こうして読み込んで取り出す

text = "PicoRubyKaigiへようこそ"
x = 16                  # 右端の外から始める

matrix.pen = 0xC0       # 文字の明るさ（draw_text は明るさを取らないので pen で決める）

while true
  matrix.clear_drawing
  matrix.draw_text(text, x, 0)   # x は文字列の左端。負になると左へはみ出す
  matrix.blit
  matrix.show

  x -= 1                                   # 1 ドット左へ
  x = 16 if x < -(text.size * 16)          # 流れ切ったら右端へ戻す（1 文字 16 ドットの概算）

  sleep_ms 90           # 流れる速さ
end
