# エンベロープ（音量が時間で変わる）を 7 通り、順に鳴らして聴き比べる。約 35 秒。
# MML の s<形> と m<周期> で指定する。v を書くと固定の音量に戻る。
# 実機専用（シミュレータの音源にはこの機能が無い）。

require 'picorubykaigi01'
GC.start                               # 読み込みで使ったメモリを片付ける
require 'picorubykaigi01/speaker'      # スピーカー
GC.start

def play(title, mml)
  puts title
  speaker.reset          # 前の曲の設定を消す（エンベロープも固定の音量に戻る）
  speaker.play_mml(mml)
  sleep_ms 200
  while speaker.playing? # 鳴り終わるまで待つ
    sleep_ms 100
  end
  sleep_ms 400
end

# s の形: 0 下がって終わり / 8 下がるのを繰り返す / 10 下がる・上がるを繰り返す / 13 上がってそのまま
# m の周期: 音量 16 段を上から下まで行く時間 = 16 × 周期 ÷ 22050 秒（m300 で約 0.2 秒、m1000 で約 0.7 秒）
play "1. 固定の音量（比較用）",            "t100 o4 l4 v15 c e g >c"
play "2. 減衰 s0 m300 — はじく音",         "t100 o4 l4 s0 m300 c e g >c"
play "3. 長い減衰 s0 m1500",               "t100 o4 l1 s0 m1500 c"
play "4. ふくらむ s13 m800",               "t100 o4 l1 s13 m800 c"
play "5. 揺れる s10 m120 — トレモロ",      "t100 o4 l1 s10 m120 c"
play "6. 速く回す s8 m12 — 音色が変わる",  "t100 o3 l2 s8 m12 c e g >c"
# 和音は 3 トラック。設定のあとに短い休符 r8 を置くと、3 声の出だしが揃う（設定の処理に数十 ms かかるため）
play "7. 和音で減衰 s0 m700",
     ["t100 o4 l1 s0 m700 r8 c r c", "t100 o4 l1 s0 m700 r8 e r e", "t100 o4 l1 s0 m700 r8 g r g"]

speaker.stop
puts "done"
