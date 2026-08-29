# LED マトリクス Gem — 計画

picorubykaigi01-board（RP2350A / 16×16 LED マトリクス）を PicoRuby から
使えるようにするための、最初のまとまった作業単位。

## 全体のゴールとこの計画の位置づけ

最終目標は「基板が動き、PicoRuby のサンプルプログラムが揃っている」こと。
基板は製造中なので、Raspberry Pi Pico 2 W を開発機にして先行できる部分を進める。

| | やること | 実基板 | 状態 |
|---|---|---|---|
| 済 | Docker ビルド環境、`rake docker:...`、SWD 書き込み | 不要 | 完了 |
| **今回** | **LED マトリクスドライバ Gem（IS31FL3729）** | **不要** | 計画 |
| 次 | 表示層 + サンプルプログラム群 | 不要 | 計画 |
| 後 | 音声(PWM)・ボタン・GROVE の各 Gem | 一部必要 | 未着手 |
| 後 | 基板専用 build_config とボード定義（RP2350A / W25Q64 / 12MHz） | 必要 | 未着手 |
| 後 | 実基板ブリングアップ、実装検査スクリプト | 必要 | 未着手 |

基板全体の Gem 構成は [../board-gems/](../board-gems/) を参照。

## 文書

- [plan.md](plan.md) — 実装計画。設計方針、フェーズ、API 案、リスク
- [hardware.md](hardware.md) — 基板とデータシートから抽出したハード仕様。
  I2C アドレス、レジスタマップ、PWM アドレス計算式、要確認事項

## 一行でいうと

`IS31FL3729`（汎用チップドライバ）と `LedMatrix`（表示層）に分け、
表示層のバックエンドを差し替え可能にする。そうすると
**実チップが無い今でも Pico 2 W 実機でサンプルプログラムまで書き切れる**。
レジスタ層は I2C をモックしてホストで単体テストする。

## 出典

- **GPIO 割当の正**: `ref/picorubykaigi01-board/docs/PicoBoard_BOM_pin_assignment_20260824.xlsx`
  （`.kicad_pcb` から機械抽出。`変更点・要確認` シートにファーム向けの注意あり）
- **製造データ**: `ref/picorubykaigi01-board/production/r1/`（netlist / positions / 回路図PDF / BOM）
- データシート: `ref/external_info/data_sheet/IS31FL3729.pdf` (Rev.D, 2021-12-16)
- ⚠️ `docs/gpio_assignment.md` は失効。詳細は hardware.md §6
- PicoRuby 側の手本: `mrbgems/picoruby-ssd1306`, `mrbgems/picoruby-aht25`,
  `mrbgems/picoruby-vram`, `mrbgems/picoruby-shinonome`
- テストの回し方: `docs/testing-guide.md`
- ライブラリ実装規約: `AGENTS.md`
