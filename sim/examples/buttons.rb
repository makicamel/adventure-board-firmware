# ボタンでドットを動かす。A で明るく、B で十字線。押しっぱなしで連続して動く。
# シミュレータでは画面のボタンか、キーボード（矢印キー / Z=A / X=B）。

require 'picorubykaigi01'
GC.start                               # 読み込みで使ったメモリを片付ける
require 'picorubykaigi01/led_matrix'   # LED マトリクス
GC.start
require 'picorubykaigi01/buttons'      # ボタン
GC.start

DELAY = 6      # 押しっぱなしにしてから連続で動き出すまで（ループ何周ぶんか）
INTERVAL = 2   # 連続で動く間隔（同じくループ何周ぶんか）

x = 8
y = 8
held = { up: 0, down: 0, left: 0, right: 0 }   # 各ボタンを押し続けている周回数

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

while true
  buttons.each_press do |name|         # 前回から今までに押されたボタンを順に取り出す（短い押しも逃さない）
    move.call(name)
    held[name] = 0 if held.key?(name)
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

  matrix.clear
  matrix.set(x, y, buttons.pressed?(:a) ? 0xFF : 0x50)   # A を押しているあいだ明るく
  if buttons.pressed?(:b)                                # B を押しているあいだ十字線
    i = 1
    while i <= 16
      matrix.set(i, y, 0x18)
      matrix.set(x, i, 0x18)
      i += 1
    end
  end
  matrix.show

  sleep_ms 60
end
