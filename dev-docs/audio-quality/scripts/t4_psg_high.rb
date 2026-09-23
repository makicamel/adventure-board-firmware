# T4: 高い音階（o6〜o7）を矩形波と三角波で。
# 矩形波だけ、音程と関係ない音（ピー、キーンという別の高さ）が混じるなら折り返し（S2）。
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
  speaker.stop
  sleep_ms 800
end

play_and_wait("T4: 矩形波 o6〜o7 の音階", "t90 @0 v12 o6 l8 cdefgab>cdefgab>c")
play_and_wait("T4: 三角波 o6〜o7 の音階", "t90 @1 v12 o6 l8 cdefgab>cdefgab>c")
puts "T4: おわり"
