# T9: 音量を下げていく。三角波 440Hz を v15 → v12 → v9 → v6 → v3（各 2 秒）、
# 続けて矩形波で同じことをする。
#   小さい音ならきれい         → クリップ（H2）か、鳴らしたときの電源の揺れ（H3）
#   小さくしてもざらざらのまま → 音量に関係ない雑音（電源ノイズ、アンプ・スピーカー自体）
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/speaker'
GC.start

def play_and_wait(label, mml)
  puts label
  speaker.play_mml(mml)
  # speaker.playing? では待てない: MML を最後まで再生しても true のまま（Player が
  # 自然に終わったとき @stopped を立てない）。全音符 1 個 = t120 で 2 秒なので時間で待つ
  sleep_ms 2300
  speaker.stop
  sleep_ms 600
end

[["三角波", 1], ["矩形波", 0]].each do |name, timbre|
  [15, 12, 9, 6, 3].each do |v|
    play_and_wait("T9: #{name} 440Hz v#{v}", "t120 @#{timbre} v#{v} o4 l1 a")
  end
end
puts "T9: おわり"
