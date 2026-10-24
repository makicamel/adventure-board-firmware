# チュートリアル 5: MML でメロディを鳴らす。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを回収する

speaker = AdventureBoard.speaker       # スピーカー。使う部品は、こうして読み込んで取り出す

speaker.reset
speaker.play_mml("t120 o4 l8 c d e f g4 g4 a a a a g2")
