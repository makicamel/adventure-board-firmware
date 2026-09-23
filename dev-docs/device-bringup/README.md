# 実機ブリングアップ

Pico 2 W（基板が来るまでの開発機）に R2P2 を焼いて、実際に触って分かったこと。

| 文書 | 内容 |
|---|---|
| [flashing-from-wsl.md](flashing-from-wsl.md) | **WSL から RP2350 を焼いてデバッグする。** usbipd、tty、openocd のリセット、BOOTSEL からの復旧、ファームが黙って死ぬ場所。この repo に限らず使える話 |
| [require-memory.md](require-memory.md) | **PicoRuby で `require` はいくらかかるか。** `/lib` のライブラリが読めなかった件の計測と、そこから決めた設計 |
| [probe-workflow.md](probe-workflow.md) | **Debug Probe だけで基板を触る手順書。** 繋ぐ・渡す・焼く・触る・切り分ける・落とし穴。USB が無いときの標準手順 |
| [r1-board.md](r1-board.md) | **r1 試作基板の初回ブリングアップ。** USB が死んでいる基板に J2 から焼いて UART で起動ログを見るまで。halt が効かない件 |
| `scripts/l_shape.rb` `left_column.rb` `frame.rb` `checker.rb` `forgot_setup.rb` | **LED マトリクスの検証用。** 上下のドライバの境目をまたぐ L 字、下半分の列の左右反転（左端の縦線）、向き（枠と対角線）、明るさ 2 段の市松、電流と倍率を書き忘れると光らない例。もとは `sim/examples/` にあったが、一般ユーザ向けのサンプルではないのでここへ移した（2026-09-22）。シミュレータで見るときは欄に貼って Run |
| [scripts/header_check.rb](scripts/header_check.rb) | **J1（ブレッドボード用ヘッダ）の疎通確認。** ジャンパなしの短絡検査 → 折り返し 1 周（2 本ずつ + 25-26-27 の数珠つなぎ）→ 電源ピン（3V3 / 5V 分圧 / GND を ADC と GPIO で）。A ボタンで段階を進める |
| [ds100-oscilloscope.md](ds100-oscilloscope.md) | **DS100（ハンディオシロ）の使い方。** キーとホイール、X1 / X10 の使い分け（最小 10mV/div は X1 のとき）、自動計測、A−B、BMP / CSV の保存と取り出し、GND の取り方 |
| [tooling.md](tooling.md) | `tools/r2p2dev.py` — 上の面倒を全部引き受けるコマンド |
