# 基板 2 枚を GROVE-B でつなぎ、自分のボタンで相手のドットを動かす。2 枚とも同じこのコードを走らせる。
# 起動したら ↑ か ↓ で役割（A / B）を選ぶ。2 枚で違う役割にすること。ケーブルは普通のストレートでよい。
# 実機専用（シミュレータでは動かない）。配線の事情は examples/README.md。

require 'adventure_board/led_matrix'   # LED マトリクス
GC.start                               # 読み込みで使ったメモリを片付ける
require 'adventure_board/buttons'      # ボタン
GC.start
require 'adventure_board/grove_link'   # GROVE-B の基板間リンク
GC.start

matrix = AdventureBoard.matrix         # ライブラリから使う部品を取り出す
buttons = AdventureBoard.buttons

matrix.clear
matrix.pen = 0x40
matrix.draw_text("?", 4, 0)            # 役割を選ぶまでは "?" を出して、何も送らない
matrix.show

role = nil
while role.nil?
  buttons.each_press do |name|
    role = :a if name == :up           # ↑ で A
    role = :b if name == :down         # ↓ で B
  end
  sleep_ms 20
end

matrix.clear
matrix.draw_text(role == :a ? "A" : "B", 4, 0)   # 選んだ役割を見せる。相手と同じ文字なら、どちらかがやり直す
matrix.show
sleep_ms 600

link = AdventureBoard.grove_link(role: role)    # 役割によって、送る線と受ける線が入れ替わる

CODES = { up: "u", down: "d", left: "l", right: "r", a: "a", b: "b" }           # 送るのはボタン名の頭 1 文字
MOVES = { "u" => [0, -1], "d" => [0, 1], "l" => [-1, 0], "r" => [1, 0] }        # 受けた文字 → 動かす量

x = 8
y = 8

matrix.clear
matrix.set(x, y)
matrix.show

while true
  buttons.each_press do |name|         # 自分のボタンは相手へ送るだけ。自分のドットは動かさない
    code = CODES[name]
    link.puts(code) if code
  end

  moved = false
  while (code = link.gets)             # 相手から届いたぶんを全部取り出す（無ければ nil）
    if (d = MOVES[code])
      x += d[0]
      y += d[1]
      x = 1 if x < 1                   # 端で止める
      x = 16 if 16 < x
      y = 1 if y < 1
      y = 16 if 16 < y
      moved = true
    elsif code == "a"                  # A は全体を一瞬光らせる
      matrix.fill(0x20)
      matrix.show
      sleep_ms 80
      moved = true
    elsif code == "b"                  # B は中央へ戻す
      x = 8
      y = 8
      moved = true
    end
  end

  if moved
    matrix.clear
    matrix.set(x, y)
    matrix.show
  end

  puts "受信が追いついていない" if 0 < link.lost   # 読みに来るのが遅すぎて取りこぼしたら知らせる

  sleep_ms 20
end
