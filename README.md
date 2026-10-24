# Adventure Board firmware

[PicoRubyKaigi 2026](https://picorubykaigi.org/) の学習用基板 **Adventure Board** のファームウェアです。
中身は [PicoRuby](https://github.com/picoruby/picoruby) と、そのシェル環境
[R2P2](https://github.com/picoruby/picoruby/tree/master/mrbgems/picoruby-r2p2) です。
PicoRuby / R2P2 そのものの説明（言語、シェルのコマンド、ビルドの仕組み）は本家を見てください。
ここにはこの基板に固有のことだけを書きます。

## 基板

| | |
|---|---|
| マイコン | RP2350A（Raspberry Pi Pico 2 相当。無線なし） |
| LED マトリクス | 白 LED 16×16。LED ドライバ IS31FL3729 × 2（上半分 / 下半分）、I2C |
| 音 | PWM → RC フィルタ → PAM8302A → スピーカー。音源は PicoRuby の PSG（3 声） |
| ボタン | 十字（↑ ← → ↓）と A / B の 6 個 |
| LED | 緑のステータス LED（プログラムから操作できる）、赤の電源 LED |
| GROVE | 2 口（I2C と、UART / PIO） |
| J1 | ブレッドボード用 2×10 ヘッダ（GPIO 13 本、3V3 / 5V / GND） |

## まず動かす

1. **ファームを焼く。** BOOTSEL を押しながら USB をつなぎ、現れたドライブに `.uf2` をコピーします。
   `.uf2` は [Releases](https://github.com/picorubykaigi/adventure-board-firmware/releases) か、自分でビルドした `dist/picoruby-pico2-prod/` にあります。
2. **USB でつなぐ。** R2P2 のシェル（`$>`）が USB シリアルに出ます。ポートは 3 つ見えるので、`$>` が出るものを選びます。
3. **サンプルを走らせる。** シェルで `/home/examples/01_light.rb` のようにパスを打つと動きます。
   最初の起動でファームが `/lib`（ボードライブラリ）と `/home/examples`（サンプル）を書き出します。

ブラウザで使うほうが楽です。次の「シミュレータ」を見てください。

## シミュレータ（ブラウザ）

基板がなくても、ブラウザで同じコードを動かせます。LED マトリクス、ボタン、音が再現されます。
基板を USB でつなげば、同じページから実機で走らせたり、実機のシェルを端末として使ったりできます。

```console
rake sim:server      # → http://localhost:8080/sim/
```

- **Run**: 欄のコードをブラウザの中の基板で走らせる。
- **実機で実行**: 欄のコードを USB の先の基板に送って走らせる（`/home/run.rb`）。
- **実機の app.rb にする**: 電源を入れるたびに動く、基板の「作品」にする（`/home/app.rb`）。
- **実機の端末**: R2P2 のシェルがそのまま使えます（`ls`、`free`、`irb`、`vim` …）。

ページのコードは [`sim/`](sim/) にあり、[sim/README.md](sim/README.md) に仕組みと注意（漢字と図形を出すにはローカルで
`rake sim:wasm` した wasm が要る、など）があります。公開版は準備中です。

## プログラムの書き方

サンプルは [`sim/examples/`](sim/examples/)（シミュレータでも実機でも動く 12 本）と
[`examples/`](examples/)（実機だけ: GROVE で基板 2 枚をつなぐ、音のエンベロープ）にあります。
まず `01_light.rb` を読んでください。

```ruby
require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを回収する

matrix = AdventureBoard.matrix         # LED マトリクス。使う部品は、こうして読み込んで取り出す

matrix.clear       # 全部消す
matrix.set(1, 1)   # x=1, y=1（左上）を点ける。座標は 1〜16
matrix.show        # ここで初めて LED に反映される
```

**ボードライブラリ `adventure_board`** がハードを Ruby から見えるようにしています（`lib/adventure_board/`）。
`require 'adventure_board'` の 1 行のあと、使う部品を `AdventureBoard` から取り出して変数に入れます。
部品のファイルは、取り出したときに初めて読み込まれます（1 本読むごとに約 28KB のメモリを使うので、使わないものは読みません）。

| 部品 | 取り出し方と使えるもの |
|---|---|
| `led_matrix` | `matrix = AdventureBoard.matrix`。`matrix.set(x, y, 明るさ)` `clear` `fill` `show` `brightness=`、描画 `draw_text` `draw_line` `draw_rect` `clear_drawing` `blit`、`pen=` |
| `buttons` | `buttons = AdventureBoard.buttons`。`buttons.each_press { \|name\| }`（押した分を順に取り出す）、`pressed?(:a)`（いま押されているか）。名前は `:up :down :left :right :a :b` |
| `speaker` | `speaker = AdventureBoard.speaker`。`speaker.play_mml("t120 o4 l8 cdefgab>c")`（MML。3 声まで、`loop: true`）、`note_on` / `note_off`、`stop`、`reset` |
| `status_led` | `led = AdventureBoard.status_led`。`led.on` / `off` / `toggle` |
| `grove_link` | `AdventureBoard.grove_link(role: :a)`。GROVE で基板 2 枚をつなぐ（`examples/grove_link_chat.rb`） |

- 繰り返しは `while true` と `sleep_ms` で書きます。シミュレータでも実機でも同じです。
- ボタンは押した瞬間がキューに積まれるので、ループが遅くても取りこぼしません。
- 明るさは見た目に比例するよう補正してあります（`set` の 3 番目の引数、0〜255）。
- 音の記法（MML）は [picoruby-midibase-mml の README](mrbgems/picoruby-midibase-mml/README_MML.md)。
  エンベロープや音色など PSG の機能は `examples/envelope.rb` と `sim/examples/harmony.rb` に例があります。
- 時間は `sleep_ms` の回数ではなく `Machine.uptime_us` で測ると、シミュレータと実機で同じ速さになります。

**基板を PC なしで動かす**には `/home/app.rb` にプログラムを置きます。R2P2 が起動のたびに実行します
（ページの「実機の app.rb にする」がこれをします。起動時に `s` を押すと飛ばせます）。

## ビルド

ビルドはすべて Docker の中で行います（ホストには Docker だけあればよい）。

```console
rake docker:r2p2:picoruby:pico2:prod       # → dist/picoruby-pico2-prod/*.uf2, *.elf
rake docker:r2p2:picoruby:pico2:debug      # 調べるとき用（-O0。Ruby も数倍遅い）
rake docker:flash:picoruby:pico2:prod      # Debug Probe（SWD）で焼く。UF2 なら BOOTSEL でコピー
rake sim:check                             # ヘッドレスのブラウザでサンプルを全部走らせて確認
```

配布するのは **prod** です。詳細は [docker/README.md](docker/README.md)。

## 本家との違い

このリポジトリは picoruby のフォークで、`main` に基板固有のものが載っています。
本家のファイルへの変更は [dev-docs/upstream-changes.md](dev-docs/upstream-changes.md) に全部列挙してあり、
本家で直すべきものは [dev-docs/upstream-issues.md](dev-docs/upstream-issues.md) に記録しています。

基板固有の追加は次のとおりです。

| 場所 | 内容 |
|---|---|
| `lib/adventure_board*` | ボードライブラリ |
| `mrbgems/picoruby-is31fl3729/` | LED ドライバ IS31FL3729 |
| `mrbgems/picoruby-pio-uart/` | PIO で作る UART（GROVE で基板同士をつなぐ） |
| `mrbgems/picoruby-adc-capture/` | 基板自身の ADC で音の出力を録る（検証用） |
| `mrbgems/picoruby-syntax-highlight/` | シミュレータのコード欄の色付け（[family-mruby](https://github.com/family-mruby/family-mruby) から） |
| `sim/` | ブラウザのシミュレータと実機の端末 |
| `sim/examples/` `examples/` | サンプル |
| `tools/` `docker/` | 書き込み・検証・ビルドの道具 |
| `dev-docs/` | 開発の記録（ハードの仕様、実機で踏んだ穴、音の調査） |

開発の手順と落とし穴は [CLAUDE.md](CLAUDE.md) にまとめてあります。

## ライセンス

PicoRuby と同じ [MIT ライセンス](LICENSE)です。同梱している xterm.js（`sim/xterm/`）と
picoruby-syntax-highlight も MIT です。
