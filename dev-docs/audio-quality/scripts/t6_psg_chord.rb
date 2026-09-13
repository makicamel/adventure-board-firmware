# T6: 和音。2 声（ドミ）→ 3 声（ドミソ）を v15、休みをはさんで v10 で同じことをする。
# v15 の和音だけ汚く、v10 ならきれいなら、PSG のソフトクリップ（S3）。
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/speaker'
GC.start

puts "T6: v15 で 2 声 → 3 声、休み、v10 で 2 声 → 3 声（1 小節 2 秒）"
speaker.play_mml([
  "t120 @1 o4 l1 v15 c c r v10 c c",
  "t120 @1 o4 l1 v15 e e r v10 e e",
  "t120 @1 o4 l1 r v15 g r r v10 g"
])
sleep_ms 200
while speaker.playing?
  sleep_ms 100
end
speaker.stop
puts "T6: おわり"
