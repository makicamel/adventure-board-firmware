# 実機ブリングアップ

Pico 2 W（基板が来るまでの開発機）に R2P2 を焼いて、実際に触って分かったこと。

| 文書 | 内容 |
|---|---|
| [flashing-from-wsl.md](flashing-from-wsl.md) | **WSL から RP2350 を焼いてデバッグする。** usbipd、tty、openocd のリセット、BOOTSEL からの復旧、ファームが黙って死ぬ場所。この repo に限らず使える話 |
| [require-memory.md](require-memory.md) | **PicoRuby で `require` はいくらかかるか。** `/lib` のライブラリが読めなかった件の計測と、そこから決めた設計 |
| [tooling.md](tooling.md) | `tools/r2p2dev.py` — 上の面倒を全部引き受けるコマンド |
