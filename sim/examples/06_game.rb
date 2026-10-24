# チュートリアル 6: 石よけゲーム。← → で動いて、上から落ちてくる石をよける。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを回収する

matrix = AdventureBoard.matrix         # LED マトリクス。使う部品は、こうして読み込んで取り出す
buttons = AdventureBoard.buttons       # ボタン
speaker = AdventureBoard.speaker       # スピーカー

speaker.reset

x = 8          # 自分の位置（いちばん下の段）
rocks = []     # 落ちてくる石。1 つが [x, y]
score = 0      # よけた石の数
tick = 0       # ループが何周したか

while true
  buttons.each_press do |name|
    x -= 1 if name == :left
    x += 1 if name == :right
  end
  x = 1 if x < 1
  x = 16 if 16 < x

  tick += 1
  speed = 6 - score / 10           # よけるほど速くなる
  speed = 2 if speed < 2
  if tick % speed == 0
    rocks.each { |r| r[1] += 1 }                 # 石を 1 段落とす
    rocks << [rand(16) + 1, 1] if rand(3) == 0   # ときどき新しい石を出す
  end

  hit = rocks.any? { |r| r[1] == 16 && r[0] == x }
  if hit
    speaker.play_mml("t180 o3 l16 g e c")
    matrix.clear_drawing
    matrix.draw_text(score.to_s, 0, 0)  # よけた数を出す
    matrix.blit
    matrix.show
    sleep_ms 2000
    rocks = []
    score = 0
    buttons.clear_presses               # 待っているあいだに押したぶんは捨てる
    next
  end

  left = rocks.select { |r| r[1] <= 16 }   # 下まで落ちきった石は捨てて
  score += rocks.size - left.size          # その数だけ点を足す
  rocks = left

  matrix.clear
  rocks.each { |r| matrix.set(r[0], r[1], 0x60) }
  matrix.set(x, 16, 0xFF)
  matrix.show
  sleep_ms 30
end
