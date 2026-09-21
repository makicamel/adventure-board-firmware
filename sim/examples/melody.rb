# MML（音楽を文字で書く記法）でメロディを鳴らす。
# シミュレータでは、何がいつ鳴ったかをページ下の「鳴った音を見る」で確かめられる。

require 'picorubykaigi01'
GC.start                               # 読み込みで使ったメモリを片付ける
require 'picorubykaigi01/speaker'      # スピーカー
GC.start

speaker.reset   # 前のプログラムが残した音量や音色の設定を初期値に戻す

# t140 テンポ / o4 オクターブ / l8 音符の長さの既定値（8 分）/ c d e f g a b ドレミ / 数字はその音だけの長さ
speaker.play_mml("t140 o4 l8 ccggaag4 ffeeddc4")
