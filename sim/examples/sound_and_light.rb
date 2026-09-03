# 音に合わせてマトリクスを光らせる。

# require したファイルは、コンパイラをヒープに残していく。
# 1 本読むたびに GC で片付けないと、次が読めなくなる。
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/led_matrix'
GC.start
require 'picorubykaigi01/speaker'
GC.start

speaker.play_mml("t120 o4 l8 cdefgab>c<bagfedc", loop: true)

t = 0
while true
  t += 1
  matrix.clear

  # 高さが上下するバー。
  h = 8 + (((t % 16) - 8).abs)
  x = 1
  while x <= 16
    y = 16
    while 16 - h < y
      matrix.set(x, y, 0x40)
      y -= 1
    end
    x += 1
  end

  # 先頭の点。
  matrix.set((t % 16) + 1, 1, 0xFF)
  matrix.show

  sleep_ms 100
end
