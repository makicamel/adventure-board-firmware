# T2 / T3: PSG で T1 と同じ高さ（262 / 440 / 880Hz）を 1 声ずつ鳴らす。
#   T2 = 矩形波（@0）を v15 と v10
#   T3 = 三角波（@1）を v15 と v10
# 判定:
#   T1 はきれい、T2 は汚い、T3 はきれい → 折り返し（S2）
#   T1 はきれい、T2 も T3 も汚い       → キャリア（S1）
require 'adventure_board/speaker'
GC.start

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

[["T2: 矩形波", 0], ["T3: 三角波", 1]].each do |name, timbre|
  [15, 10].each do |v|
    # t60 の全音符 = 4 秒。c4 = 262Hz、a4 = 440Hz、a5 = 880Hz
    play_and_wait("#{name} v#{v}: 262 / 440 / 880Hz",
                  "t60 @#{timbre} v#{v} o4 l2 c r4 a r4 > a")
  end
end
puts "T2/T3: おわり"
