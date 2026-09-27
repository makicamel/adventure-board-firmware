# T8: パン（S4）の確認。同じ 440Hz を、パン中央（p8）と左いっぱい（p0）で鳴らす。
# 基板のスピーカーは左（GPIO10）だけに繋がっているので、p0 のほうが約 3dB 大きいはず。
# 同じ大きさに聞こえるなら、パンが効いていない。
# あわせて、Board が起動時に送っている「左に振る」設定が効いているかも分かる:
# 1 回目（p を書かない）が p0 と同じ大きさなら効いている、p8 と同じなら効いていない。
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

play_and_wait("T8: パン指定なし（Board の既定）", "t60 @1 v15 o4 l2 a")
play_and_wait("T8: パン中央 p8", "t60 @1 v15 p8 o4 l2 a")
play_and_wait("T8: パン左いっぱい p0", "t60 @1 v15 p0 o4 l2 a")
puts "T8: おわり"
