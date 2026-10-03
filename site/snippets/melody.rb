require 'adventure_board'
GC.start

speaker = AdventureBoard.speaker

speaker.reset
speaker.play_mml("t120 o4 l8 c d e f g4 g4 a a a a g2")
