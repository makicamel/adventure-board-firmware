# dev-docs

picorubykaigi01-board のファームウェア開発メモ。

| フォルダ | 内容 |
|---|---|
| [board-gems/](board-gems/) | **基板の全機能を Ruby から触るための Gem 棚卸し**。何を新規に作り、何を既存 gem で賄うか。Gem の置き場所 |
| [led-matrix-gem/](led-matrix-gem/) | 最初の作業単位。LED マトリクス（IS31FL3729）の実装計画と、基板から抽出したハード仕様 |
| [wasm-simulator/](wasm-simulator/) | ブラウザで 16×16 の光り方を目視するシミュレータ（PicoRuby.wasm）。座標マッピングの検証手段 |

ハード仕様の正は `ref/picorubykaigi01-board/production/r1/`（製造データ）と
`ref/picorubykaigi01-board/docs/PicoBoard_BOM_pin_assignment_20260824.xlsx`（GPIO 割当）。
`docs/gpio_assignment.md` は失効しているので参照しないこと。
