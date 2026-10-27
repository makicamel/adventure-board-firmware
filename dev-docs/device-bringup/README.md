# 実機ブリングアップ

Pico 2 W（基板が来るまでの開発機）に R2P2 を焼いて、実際に触って分かったこと。

| 文書 | 内容 |
|---|---|
| [flashing-from-wsl.md](flashing-from-wsl.md) | **WSL から RP2350 を焼いてデバッグする。** usbipd、tty、openocd のリセット、BOOTSEL からの復旧、ファームが黙って死ぬ場所。この repo に限らず使える話 |
| [require-memory.md](require-memory.md) | **PicoRuby で `require` はいくらかかるか。** `/lib` のライブラリが読めなかった件の計測と、そこから決めた設計 |
| [task-memory.md](task-memory.md) | **終わった Task はメモリに残る。** `Task#close` するまで解放されない作り。`play_mml` をくり返すと `NoMemoryError` になる件の原因と、`/lib` の `Speaker` だけで直した方法と、実機での測定 |
| [probe-workflow.md](probe-workflow.md) | **Debug Probe だけで基板を触る手順書。** 繋ぐ・渡す・焼く・触る・切り分ける・落とし穴。USB が無いときの標準手順 |
| [r1-board.md](r1-board.md) | **r1 試作基板の初回ブリングアップ。** USB が死んでいる基板に J2 から焼いて UART で起動ログを見るまで。halt が効かない件 |
| [pv1-board.md](pv1-board.md) | **PV1 基板（r1 の次の版）。** USB から UF2 で焼く手順と、r1 で問題だった USB 接続と音が PV1 でも問題ないことの確認 |
| `scripts/l_shape.rb` `left_column.rb` `frame.rb` `checker.rb` `forgot_setup.rb` | **LED マトリクスの検証用。** 上下のドライバの境目をまたぐ L 字、下半分の列の左右反転（左端の縦線）、向き（枠と対角線）、明るさ 2 段の市松、電流と倍率を書き忘れると光らない例。もとは `sim/examples/` にあったが、一般ユーザ向けのサンプルではないのでここへ移した（2026-09-22）。シミュレータで見るときは欄に貼って Run |
| [scripts/header_check.rb](scripts/header_check.rb) | **J1（ブレッドボード用ヘッダ）の疎通確認。** ジャンパなしの短絡検査 → 折り返し 1 周（2 本ずつ + 25-26-27 の数珠つなぎ）→ 電源ピン（3V3 / 5V 分圧 / GND を ADC と GPIO で）。A ボタンで段階を進める |
| [scripts/grove2_check.rb](scripts/grove2_check.rb) | **GROVE2（J5）の疎通確認。** Grove → ジャンパ変換ケーブルでブレッドボードに出し、短絡なし → 黄・白の折り返し（色とピンの対応）→ 電源（抵抗 2 本で半分にして ADC。3.3V か 5V か分かる）と GND → PIO の UART で 0〜255 を折り返す。A ボタンで段階を進める。PV1 で全段 OK（2026-10-04） |
| [ds100-oscilloscope.md](ds100-oscilloscope.md) | **DS100（ハンディオシロ）の使い方。** キーとホイール、X1 / X10 の使い分け（最小 10mV/div は X1 のとき）、自動計測、A−B、BMP / CSV の保存と取り出し、GND の取り方 |
| [tooling.md](tooling.md) | `tools/r2p2dev.py` — 上の面倒を全部引き受けるコマンド |
