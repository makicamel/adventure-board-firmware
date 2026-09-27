# T25: T23 と同じ曲と記録。ボタンを待たず 8 秒で自分で止まる（直近 2.6 秒が残る）
require 'adventure_board/speaker'
GC.start

speaker = AdventureBoard.speaker
speaker.reset
puts "T25: addr=#{ADCCapture.addr}"
ADCCapture.start(26, 12500)
speaker.play_mml("t140 o4 l8 $ ccggaag4 ffeeddc4 r2", loop: true)
sleep_ms 8000
oldest = ADCCapture.stop
puts "T25: stopped oldest=#{oldest}"
sleep_ms 3000
speaker.stop
puts "T25: done"
