# ステータス LED（緑）を点滅させる。
#
# GPIO16 の先に R31 と LED があり、High で点く。
# 隣の赤は 3V3 直結の電源表示で、ソフトからは触れない。
#
# A を押している間は点きっぱなし、それ以外は 1 秒周期で点滅する。

# require したファイルは、コンパイラをヒープに残していく。
# 1 本読むたびに GC で片付けないと、次が読めなくなる。
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/led_matrix'
GC.start
require 'picorubykaigi01/buttons'
GC.start
require 'picorubykaigi01/status_led'
GC.start

led = board.status_led

t = 0
while true
  t += 1

  if buttons.pressed?(:a)
    led.on
  elsif (t % 10) == 0
    led.toggle
  end

  # 押されたぶんだけドットを増やす、ついでのデモ。
  buttons.each_press do |name|
    matrix.set(rand(16) + 1, rand(16) + 1, 0x80) if name == :b
    matrix.show
  end

  sleep_ms 100
end
