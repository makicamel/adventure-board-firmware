# dev-docs

picorubykaigi01-board のファームウェア開発メモ。

| フォルダ | 内容 |
|---|---|
| [board-gems/](board-gems/) | **基板の全機能を Ruby から触るための Gem 棚卸し**。何を新規に作り、何を既存 gem で賄うか。Gem の置き場所 |
| [led-matrix-gem/](led-matrix-gem/) | 最初の作業単位。LED マトリクス（IS31FL3729）の実装計画と、基板から抽出したハード仕様 |
| [wasm-simulator/](wasm-simulator/) | ブラウザで 16×16 の光り方を目視するシミュレータ（PicoRuby.wasm）。座標マッピングの検証手段 |
| [audio-quality/](audio-quality/) | スピーカーの音が汚い原因の調査。**経緯と次の手順は report.md**（PWM の切り替え自体でノイズ、GND の回り込みが有力） |
| [r2-board-notes.md](r2-board-notes.md) | **r2 基板への要望**（J2 を 2×3 ソケットに、GROVE のピン順、音声フィルタ、ボタンの資料） |
| [upstream-changes.md](upstream-changes.md) | upstream のファイルに入れた変更の全部と理由 |
| [upstream-issues.md](upstream-issues.md) | **upstream で見つけた問題**（PR 用の記録）。IRQ のデバウンス、スクリプト終了後も残る割り込み登録 |

ハード仕様の正は `ref/picorubykaigi01-board/production/r1/`（製造データ）と
`ref/picorubykaigi01-board/docs/PicoBoard_BOM_pin_assignment_20260824.xlsx`（GPIO 割当）。
`docs/gpio_assignment.md` は失効しているので参照しないこと。
