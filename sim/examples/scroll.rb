# 文字を右から左へ流す。
text = "PicoRubyKaigi 第一回 ようこそ"
x = 16

while true
  matrix.clear_drawing
  matrix.draw_text(text, x, 0)
  matrix.blit(on: 0xC0)
  matrix.show

  x -= 1
  # 全部流れ切ったら右端へ戻す。全角 1 文字 16px の概算。
  x = 16 if x < -(text.size * 16)

  sleep_ms 90
end
