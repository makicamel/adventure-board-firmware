# 実機ブリングアップ

Pico 2 W（基板が来るまでの開発機）に R2P2 を焼いて、実際に触って分かったこと。

| 文書 | 内容 |
|---|---|
| [flashing-from-wsl.md](flashing-from-wsl.md) | **WSL から RP2350 を焼いてデバッグする。** usbipd、tty、openocd のリセット、BOOTSEL からの復旧、ファームが黙って死ぬ場所。この repo に限らず使える話 |
| [require-memory.md](require-memory.md) | **PicoRuby で `require` はいくらかかるか。** `/lib` のライブラリが読めなかった件の計測と、そこから決めた設計 |
| [probe-workflow.md](probe-workflow.md) | **Debug Probe だけで基板を触る手順書。** 繋ぐ・渡す・焼く・触る・切り分ける・落とし穴。USB が無いときの標準手順 |
| [r1-board.md](r1-board.md) | **r1 試作基板の初回ブリングアップ。** USB が死んでいる基板に J2 から焼いて UART で起動ログを見るまで。halt が効かない件 |
| [tooling.md](tooling.md) | `tools/r2p2dev.py` — 上の面倒を全部引き受けるコマンド |
