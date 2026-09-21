# エンベロープ（音量が時間で変わる）を聴き比べる。実機専用。
#
# PSG は音量を「固定」にするか「エンベロープに任せる」かをチャンネルごとに選べる。
# MML では s と m の 2 つで指定する。v を書くと固定の音量に戻る。
#
#   s<形>    エンベロープを使う。形は 0〜15（よく使うのは下の 4 つ）
#              0  下がって終わり（減衰）      8  下がるのを繰り返す（のこぎり）
#             10  下がる・上がるを繰り返す   13  上がって、そのまま
#   m<周期>  1 段進むのにかけるサンプル数。音量は 16 段なので、
#            上から下まで 16 × 周期 ÷ 22050 秒。m300 なら約 0.2 秒、m1000 なら約 0.7 秒
#
# 形と周期のレジスタは 3 チャンネルで 1 組。どのトラックに書いても全体に効く。
# シミュレータの音源（WebAudio）には無い機能なので、ブラウザでは固定の音量で鳴る。

require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/speaker'
GC.start

def play(title, mml)
  puts title
  speaker.reset          # 前の曲のエンベロープの設定を消す（v が固定の音量に戻す）
  speaker.play_mml(mml)
  sleep_ms 200
  while speaker.playing?
    sleep_ms 100
  end
  sleep_ms 400
end

play "1. 固定の音量（比較用）",            "t100 o4 l4 v15 c e g >c"
play "2. 減衰 s0 m300 — はじく音",         "t100 o4 l4 s0 m300 c e g >c"
play "3. 長い減衰 s0 m1500",               "t100 o4 l1 s0 m1500 c"
play "4. ふくらむ s13 m800",               "t100 o4 l1 s13 m800 c"
play "5. 揺れる s10 m120 — トレモロ",      "t100 o4 l1 s10 m120 c"
play "6. 速く回す s8 m12 — 音色が変わる",  "t100 o3 l2 s8 m12 c e g >c"
# 3 声とも同じ速さで減衰する。
# 設定（s / m）のあとに短い休符 r8 を置いている。イベントは 1 つずつ Ruby で処理され、
# 設定は 1 つ数十 ms かかる。休符なしで「設定 → 音」を 3 トラックぶん並べると、
# 1 声目が鳴ってから 3 声目が鳴るまで 0.3 秒ほどずれて、和音がばらけて聞こえる。
play "7. 和音で減衰 s0 m700",
     ["t100 o4 l1 s0 m700 r8 c r c", "t100 o4 l1 s0 m700 r8 e r e", "t100 o4 l1 s0 m700 r8 g r g"]

speaker.stop
puts "done"
