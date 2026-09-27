# T22: PSG の音を鳴らしっぱなしにして、J3（生の PWM）をオシロで撮る。
# パルス幅を 1 周期ずつ読めば、PSG が出したサンプル列をそのまま復元できる。
#   オシロ: J3、X1、DC、1V/div、2ms/div で P → CSV（5MS/s × 100,000 点 = 20ms ≒ 440Hz の 9 周期）
# TIMBRE を変えて流す: 1 = 三角波、0 = 矩形波。全音符 8 秒（t30）をループ。止めるにはリセット。
require 'adventure_board/speaker'
GC.start

speaker = AdventureBoard.speaker

TIMBRE = 1
# loop: true だけでは繰り返さない。MML に繰り返しの開始位置 "$" が要る
speaker.play_mml("t30 @#{TIMBRE} v15 o4 l1 $ a", loop: true)
puts "T22: timbre #{TIMBRE} を鳴らしている"
