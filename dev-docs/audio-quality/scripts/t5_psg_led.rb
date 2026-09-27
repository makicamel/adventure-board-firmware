# T5: 同じ音を、LED マトリクス消灯のときと、市松模様で点灯しているときで比べる。
# 点灯中だけ汚い・ジーという音が乗るなら、電源ノイズ（H3）。
# 全点灯 + 音声は USB 500mA を超えるおそれがあるので、半分だけ点ける。
require 'adventure_board/led_matrix'
GC.start
require 'adventure_board/speaker'
GC.start

matrix = AdventureBoard.matrix
speaker = AdventureBoard.speaker

def play_and_wait(label, mml)
  speaker = AdventureBoard.speaker
  puts label
  speaker.play_mml(mml)
  sleep_ms 200
  while speaker.playing?
    sleep_ms 100
  end
  speaker.stop
  sleep_ms 800
end

mml = "t60 @1 v15 o4 l2 a r4 a"

matrix.clear
matrix.show
play_and_wait("T5: LED 消灯で 440Hz 三角波", mml)

y = 1
while y <= 16
  x = 1
  while x <= 16
    matrix.set(x, y, 0x80) if (x + y) % 2 == 0
    x += 1
  end
  y += 1
end
matrix.show
play_and_wait("T5: LED 市松点灯で 440Hz 三角波", mml)

matrix.clear
matrix.show
play_and_wait("T5: もう一度 LED 消灯で", mml)
puts "T5: おわり"
