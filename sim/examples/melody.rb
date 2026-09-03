# MML でメロディを鳴らす。
#
# パーサもシーケンサも実機と同じ picoruby-midibase-mml が動いている。
# 差し替わっているのは音源だけ（実機は PSG、ここは WebAudio）。
#
# 音を聞くには先に「音を有効にする」を押す。押さなくても、
# 何がいつ鳴ったかは下のノートログに出る。
#
#   t120  テンポ    o4  オクターブ    l8  既定の音符長
#   >  オクターブ上げ    <  下げ    r  休符

# require したファイルは、コンパイラをヒープに残していく。
# 1 本読むたびに GC で片付けないと、次が読めなくなる。
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/speaker'
GC.start

speaker.play_mml("t140 o4 l8 ccggaag4 ffeeddc4")
