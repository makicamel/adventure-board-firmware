# PV1 基板（2026-10-03）

r1 の次の版（量産試作）。r1 で問題になった部分を基板側で直したもの。
このあとの量産版 V1 は、PV1 から下側の取付穴の位置とシルクの "PV1" だけを変えたもの。シミュレータの基板の絵は V1 から作っている。

## 書き込み

r1 と違い、USB がそのまま使える。Debug Probe（J2）は要らない。

1. `R2P2_CONSOLE_UART=1 rake docker:r2p2:picoruby:pico2:prod`（配布と同じ prod ビルド）
2. BOOTSEL を押しながら USB を挿す → `RP2350` ドライブに `dist/picoruby-pico2-prod/*.uf2` をコピー
3. 自動で再起動し、最初の起動で `/lib` と `/home/examples` が書き出される

初回は `19ad4b99` の prod を焼いた。

## 確認したこと

r1 で問題だった次の 2 つが、PV1 でも問題なく動くことを確かめた。基板の修正で新たに壊れてはいない。

- **USB 接続**: r1 は ESD アレイ U5 の品種違いで USB が開放になっており、手で配線して使っていた（[r1-board.md](r1-board.md)）。
  PV1 は改造なしで USB シリアルが見え、シミュレータのページから WebSerial でつながる
- **音**: r1 で直したスピーカーの音（[../audio-quality/report.md](../audio-quality/report.md)）が、PV1 でも同じように鳴る
