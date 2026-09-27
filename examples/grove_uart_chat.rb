# 基板 2 枚を GROVE-B でつなぎ、自分のボタンで相手のドットを動かす（ハードウェア UART 版）。
# 2 枚とも同じこのコードを走らせる。クロスケーブルが要る（ストレートでは送信同士がぶつかる）。
# 実機専用。ケーブルを選ばないのは grove_link_chat.rb。詳しくは examples/README.md。

require 'adventure_board/led_matrix'   # LED マトリクス
GC.start                               # 読み込みで使ったメモリを片付ける
require 'adventure_board/buttons'      # ボタン
GC.start

matrix = AdventureBoard.matrix         # ライブラリから使う部品を取り出す
buttons = AdventureBoard.buttons

uart = AdventureBoard.grove_uart(baudrate: 115200)   # GROVE-B を UART として開く

CODES = { up: "u", down: "d", left: "l", right: "r", a: "a", b: "b" }   # 送るのはボタン名の頭 1 文字 + 改行
MOVES = {                                                                # 受けた文字 → 動かす量
  "u" => [0, -1], "d" => [0, 1], "l" => [-1, 0], "r" => [1, 0]
}

x = 8
y = 8
inbox = []                             # 届いた行を溜めておく場所

uart.irq(UART::RX_RECEIVE) do |u, _event_type|   # 受信は割り込みで拾う。ループが遅くても取りこぼさない
  while (line = u.gets)
    inbox << line.chomp
  end
end

matrix.clear
matrix.set(x, y)
matrix.show

while true
  buttons.each_press do |name|         # 自分のボタンは相手へ送るだけ。自分のドットは動かさない
    code = CODES[name]
    uart.write("#{code}\n") if code
  end

  moved = false
  while (code = inbox.shift)           # 相手から届いたぶんを順に取り出す
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

  sleep_ms 30
end
