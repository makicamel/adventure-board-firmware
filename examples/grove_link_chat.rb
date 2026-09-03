# 2 枚の基板を GROVE-B で繋いで、ボタンで相手のドットを動かす。
#
# 自分のボタンが動かすのは「相手の」ドット。2 枚とも**同じこのコード**を走らせる。
#
# ⚠ 実機 2 枚が要る。ケーブルは**箱に入っているストレートのまま**でよい。
#   GPIO28 は UART の TX にしかなれないので、2 枚ともハードウェア UART を
#   使うと TX 同士がぶつかる。そこで PIO で UART を作り、片方だけ
#   TX と RX を入れ替える。それが下の「役割」。
#
# シミュレータでは動かない（PIO も相手の基板も無い）。

# require したファイルは、コンパイラをヒープに残していく。
# 1 本読むたびに GC で片付けないと、次が読めなくなる。
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/led_matrix'
GC.start
require 'picorubykaigi01/buttons'
GC.start
require 'picorubykaigi01/grove_link'
GC.start

# 役割を選ぶまでは、どちらの基板も送信しない。
# 2 枚とも同じ役割にすると TX 同士が同じ線を押し合って、通信できない。
matrix.clear
matrix.pen = 0x40
matrix.draw_text("?", 4, 0)
matrix.show

role = nil
while role.nil?
  buttons.each_press do |name|
    role = :a if name == :up
    role = :b if name == :down
  end
  sleep_ms 20
end

# 選んだ役割を出す。相手と同じ文字が出ていたら、どちらかが選び直す。
matrix.clear
matrix.draw_text(role == :a ? "A" : "B", 4, 0)
matrix.show
sleep_ms 600

link = board.grove_link(role: role)

CODES = { up: "u", down: "d", left: "l", right: "r", a: "a", b: "b" }
MOVES = { "u" => [0, -1], "d" => [0, 1], "l" => [-1, 0], "r" => [1, 0] }

x = 8
y = 8

matrix.clear
matrix.set(x, y)
matrix.show

while true
  # 自分のボタンは相手へ送るだけ。自分のドットは動かさない。
  buttons.each_press do |name|
    code = CODES[name]
    link.puts(code) if code
  end

  # 相手から届いたぶんだけ動かす。
  #
  # 受信 FIFO は 8 バイトしかなく、割り込みも無い。溜まる前に読みに来る
  # 必要があるので、ループは短く保つこと。1 回の押しが 2 バイトなので、
  # 100ms ごとに読めば 4 回ぶん溜められる。
  moved = false
  while (code = link.gets)
    if (d = MOVES[code])
      x += d[0]
      y += d[1]
      x = 1 if x < 1
      x = 16 if 16 < x
      y = 1 if y < 1
      y = 16 if 16 < y
      moved = true
    elsif code == "a"
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

  # 一周ぶん（512 バイト）溜まる前に読みに来られなかったら、それは落ちている。
  # DMA が受けているので普通は起きないが、起きたら黙っていない。
  puts "受信が追いついていない" if link.lost?

  sleep_ms 20
end
