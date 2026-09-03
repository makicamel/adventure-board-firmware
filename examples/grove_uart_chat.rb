# 2 枚の基板を GROVE-B で繋いで、ボタンで相手のドットを動かす。
#
# 自分のボタンが動かすのは「相手の」ドット。2 枚とも**同じこのコード**を走らせる。
#
# ⚠ 実機 2 枚 + **クロスケーブル**が要る。GPIO28 は TX、GPIO29 は RX にしか
#   なれないので、ストレートケーブルでは TX 同士がぶつかって動かない。
#   Seeed の Grove - UART Crossover Cable 4Pin (SS100052406) など。
#   詳しくは examples/README.md。
#
# シミュレータでは動かない（相手の基板が無い）。

# require したファイルは、コンパイラをヒープに残していく。
# 1 本読むたびに GC で片付けないと、次が読めなくなる。
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/led_matrix'
GC.start
require 'picorubykaigi01/buttons'
GC.start

uart = board.grove_uart(baudrate: 115200)

# 送るのはボタン名の頭 1 文字 + 改行。行単位なので gets で読める。
CODES = { up: "u", down: "d", left: "l", right: "r", a: "a", b: "b" }
MOVES = {
  "u" => [0, -1], "d" => [0, 1], "l" => [-1, 0], "r" => [1, 0]
}

x = 8
y = 8
inbox = []

# 受信は割り込みで拾う。ポーリングしないので、ループがどれだけ遅くても
# 取りこぼさない。ボタンと同じ考え方。
uart.irq(UART::RX_RECEIVE) do |u, _event_type|
  while (line = u.gets)
    inbox << line.chomp
  end
end

matrix.clear
matrix.set(x, y)
matrix.show

while true
  # 自分のボタンは相手へ送るだけ。自分のドットは動かさない。
  buttons.each_press do |name|
    code = CODES[name]
    uart.write("#{code}\n") if code
  end

  # 相手から届いたぶんだけ動かす。
  moved = false
  while (code = inbox.shift)
    if (d = MOVES[code])
      x += d[0]
      y += d[1]
      x = 1 if x < 1
      x = 16 if 16 < x
      y = 1 if y < 1
      y = 16 if 16 < y
      moved = true
    elsif code == "a"
      # A は光らせるだけ。
      matrix.fill(0x20)
      matrix.show
      sleep_ms 80
      moved = true
    elsif code == "b"
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
