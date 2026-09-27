# T26: エンベロープの減衰を ADC で録る（和音 s0 m700 を 1 回、2.5 秒）
require 'adventure_board/speaker'
GC.start

speaker = AdventureBoard.speaker
speaker.reset
puts "T26: addr=#{ADCCapture.addr}"
ADCCapture.start(26, 12500)
# r8: 設定（s / m）の処理を休符のあいだに済ませて、3 声の出だしを揃える（report.md §3 その 7）
speaker.play_mml(["t100 o4 l1 s0 m700 r8 c", "t100 o4 l1 s0 m700 r8 e", "t100 o4 l1 s0 m700 r8 g"])
sleep_ms 2500
oldest = ADCCapture.stop
puts "T26: stopped oldest=#{oldest}"
speaker.stop
puts "T26: done"
