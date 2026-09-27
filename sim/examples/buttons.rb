# ボタンでドットを動かす。A で輪が広がり、B で全体が光る。押しっぱなしで連続して動く。
# シミュレータでは画面のボタンか、キーボード（矢印キー / Z=A / X=B）。

require 'adventure_board/led_matrix'   # LED マトリクス
GC.start                               # 読み込みで使ったメモリを片付ける
require 'adventure_board/buttons'      # ボタン
GC.start

matrix = AdventureBoard.matrix         # ライブラリから使う部品を取り出す
buttons = AdventureBoard.buttons

DELAY = 6      # 押しっぱなしにしてから連続で動き出すまで（ループ何周ぶんか）
INTERVAL = 2   # 連続で動く間隔（同じくループ何周ぶんか）
RING_END = 22  # 輪がここまで広がったら消える（半径）

x = 8
y = 8
held = { up: 0, down: 0, left: 0, right: 0 }   # 各ボタンを押し続けている周回数
rings = []     # 広がっている輪。[中心の x, 中心の y, 半径]
flash = 0      # 全体の光の強さ。押すと 0xFF になり、だんだん消える

move = lambda do |name|
  x -= 1 if name == :left
  x += 1 if name == :right
  y -= 1 if name == :up
  y += 1 if name == :down
  x = 1 if x < 1          # 端で止める
  x = 16 if 16 < x
  y = 1 if y < 1
  y = 16 if 16 < y
end

plot = lambda do |px, py, level|       # はみ出した点は描かない
  matrix.set(px, py, level) if 1 <= px && px <= 16 && 1 <= py && py <= 16
end

# 円の周りの点だけを求める（中点円アルゴリズム）。1/8 を計算して 8 か所に写す
ring = lambda do |cx, cy, r, level|
  dx = r
  dy = 0
  err = 1 - r
  while dy <= dx
    plot.call(cx + dx, cy + dy, level)
    plot.call(cx - dx, cy + dy, level)
    plot.call(cx + dx, cy - dy, level)
    plot.call(cx - dx, cy - dy, level)
    plot.call(cx + dy, cy + dx, level)
    plot.call(cx - dy, cy + dx, level)
    plot.call(cx + dy, cy - dx, level)
    plot.call(cx - dy, cy - dx, level)
    dy += 1
    if err < 0
      err += 2 * dy + 1
    else
      dx -= 1
      err += 2 * (dy - dx) + 1
    end
  end
end

while true
  buttons.each_press do |name|         # 前回から今までに押されたボタンを順に取り出す（短い押しも逃さない）
    move.call(name)
    held[name] = 0 if held.key?(name)
    rings << [x, y, 0] if name == :a   # A: いまの位置から輪を出す
    flash = 0xFF if name == :b         # B: 全体を光らせる
  end

  held.each_key do |name|              # 押しっぱなしのあいだの連続移動
    if buttons.pressed?(name)          # pressed? は「いま押されているか」
      n = held[name] + 1
      held[name] = n
      move.call(name) if DELAY < n && (n - DELAY - 1) % INTERVAL == 0
    else
      held[name] = 0
    end
  end
  flash = 0xFF if buttons.pressed?(:b) && flash < 0x10   # B を押し続けると明滅をくり返す

  if 0 < flash
    matrix.fill(flash)                 # 全体を同じ明るさにする
    flash = flash * 6 / 10             # 次の周では少し暗く
  else
    matrix.clear
  end

  rings.each do |c|
    ring.call(c[0], c[1], c[2], 0xFF * (RING_END - c[2]) / RING_END)   # 外へ行くほど薄く
    c[2] += 1
  end
  rings = rings.select { |c| c[2] < RING_END }   # 広がりきった輪を捨てる

  matrix.set(x, y, 0xFF)               # ドットはいちばん明るく、いちばん上に
  matrix.show

  sleep_ms 60
end
