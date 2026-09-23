# T9: 音量を下げていく。三角波 440Hz を v15 → v12 → v9 → v6 → v3（各 2 秒）、
# 続けて矩形波で同じことをする。
#   小さい音ならきれい         → クリップ（H2）か、鳴らしたときの電源の揺れ（H3）
#   小さくしてもざらざらのまま → 音量に関係ない雑音（電源ノイズ、アンプ・スピーカー自体）
require 'adventure_board'
GC.start
require 'adventure_board/speaker'
GC.start

def play_and_wait(label, mml)
  puts label
  speaker.play_mml(mml)
  sleep_ms 200
  while speaker.playing?
    sleep_ms 100
  end
  # speaker.stop は呼ばない: アンプを切るので、音の合間ごとにポップ音が入る
  sleep_ms 600
end

[["三角波", 1], ["矩形波", 0]].each do |name, timbre|
  [15, 12, 9, 6, 3].each do |v|
    play_and_wait("T9: #{name} 440Hz v#{v}", "t120 @#{timbre} v#{v} o4 l1 a")
  end
end
puts "T9: おわり"
