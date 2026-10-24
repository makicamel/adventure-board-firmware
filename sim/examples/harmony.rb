# MML（音楽を文字で書く記法）で 3 声の曲を鳴らす。メロディ、分散和音、ベース。
# PSG は 3 声なので、トラックは 3 本まで。シミュレータでは、鳴った音をページ下の「鳴った音を見る」で確かめられる。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを回収する

speaker = AdventureBoard.speaker       # スピーカー。使う部品は、こうして読み込んで取り出す

speaker.reset   # 前のプログラムが残した音量や音色の設定を初期値に戻す

# 記法: t テンポ / o オクターブ / l 音符の長さの既定値 / c d e f g a b ドレミ / r 休符 / 数字はその音だけの長さ
#       < > オクターブ下げ上げ / [ ]2 繰り返し / | 小節の目印（音には関係ない） / $ ここから繰り返す
#       @ 音色（0 矩形波 1 三角波 2 鋸波） / v 音量 / s m エンベロープ（音量が時間で変わる。s0 は減衰、m は速さ）
#       設定のあとに r8 を置くと、3 本のトラックの出だしが揃う
LEAD = "t128 @0 v12 o5 l8 r8 $ e4 g e a4 g4 | e d c d e4 e4 | d4 f d g4 f4 | d c <b> c d4 r4 |" \
       "e4 g e a4 g4 | e d c d e4 e4 | d4 f d g4 f4 | c2. r4"
ARP  = "t128 @1 s0 m300 o4 l8 r8 $ [c e g e]2 | [a >c e c<]2 | [f a >c< a]2 | [g b >d< b]2 |" \
       "[c e g e]2 | [a >c e c<]2 | f a >c< a g b >d< b | c2. r4"          # はじく音: 1 音ごとに減衰する
BASS = "t128 @2 v10 o3 l4 r8 $ c c g g | a a e e | f f c c | g g d d |" \
       "c c g g | a a e e | f f g g | c2. r4"

speaker.play_mml([LEAD, ARP, BASS], loop: true)   # 3 本を同時に、$ から繰り返し
