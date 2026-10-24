# チュートリアル 3: 文字を右から左へ流す。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを回収する

matrix = AdventureBoard.matrix         # LED マトリクス。使う部品は、こうして読み込んで取り出す

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
