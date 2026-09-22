# picorubykaigi01-board-firmware

PicoRuby のフォーク。**picorubykaigi01-board**（RP2350A / 16×16 LED マトリクス /
音声 / ボタン / GROVE、PicoRubyKaigi の学習用配布基板）のファームウェアを作る。

試作基板 r1 が手元にある（**Pico 2 相当、WiFi なし**。焼くのは `pico2` ビルド）。
r1 の USB は元は死んでいたが、手で配線して USB シリアルが使えるようになっている（Windows 側では 16c0:400f、CDC が複数）。
書き込みと UART コンソールは J2 の Debug Probe から、ブラウザの WebSerial は USB から。**USB 側は WSL に attach しない**。
**手順書: [dev-docs/device-bringup/probe-workflow.md](dev-docs/device-bringup/probe-workflow.md)**
（経緯は [r1-board.md](dev-docs/device-bringup/r1-board.md)）。
基板が来るまでの開発機は **Raspberry Pi Pico 2 W** だった。

ライブラリ実装そのものの規約（サブモジュール、ブロック反復の回避、メモ化、
WebAssembly の注意）は [AGENTS.md](AGENTS.md) にある。こちらは**この repo 固有の
作業手順と、実際に踏んだ落とし穴**をまとめたもの。

## ビルドは全部 Docker

**ホストで実ビルドを走らせないこと。** ホストの ruby は 3.2.6 で、
README が要求する 3.4+ に満たない。ホストの `rake` は
タスク定義の読み込みには足りるので、`docker:*` と `sim:*` の起動には使える。

```console
rake docker:image                          # イメージを作る（無ければ自動で作られる）
rake docker:r2p2:picoruby:pico2_w:prod     # ビルド → dist/{vm}-{board}-{mode}/
rake docker:r2p2:picoruby:pico2_w:debug    # gdb 用 .elf 付き
rake docker:r2p2:picoruby:pico2_w:clean
rake docker:shell                          # コンテナ内シェル
R2P2_CONSOLE_UART=1 rake docker:r2p2:picoruby:pico2:debug   # r1 基板用: シェルを J2 の UART にも出す
rake docker:clean                          # イメージと bundle ボリュームを消す
```

`build_config/r2p2-*.rb` が存在する `{vm}:{board}:{mode}` の組み合わせだけ
タスクが生成される。詳細は [docker/README.md](docker/README.md)。

### 書き込み（PicoProbe / SWD）

```console
rake docker:flash:picoruby:pico2_w:prod
```

イメージに `raspberrypi/openocd`（`sdk-2.0.0`）を同梱してある。Debian の 0.12.0 は
RP2350 非対応で `target/rp2350.cfg` が無いため。openocd は `.uf2` ではなく
**`.elf` を焼く**。

Windows 側でプローブを WSL へ渡す（挿すたびに 1 回）:

```powershell
usbipd list
usbipd attach --wsl --busid <BUSID>
```

⚠️ **実基板の J2（SWD/UART ヘッダ）は DNP** で JLCPCB では実装されない。
PicoProbe を使うにはピンヘッダを自分で付ける。BOOTSEL は実装されるので
UF2 のドラッグ&ドロップは常に使える。

### USB の無い基板を Debug Probe だけで触る（r1 の標準手順）

手順書は [dev-docs/device-bringup/probe-workflow.md](dev-docs/device-bringup/probe-workflow.md)。要約:

```console
usbipd attach --wsl --busid 1-5                              # Windows 側。挿すたびに 1 回
R2P2_CONSOLE_UART=1 rake docker:r2p2:picoruby:pico2:debug   # シェルを J2 の UART にも出す
rake docker:flash:picoruby:pico2:debug
export R2P2_PORT=/dev/ttyACM0                                # 以後 r2p2dev.py はこの tty を使う
tools/r2p2dev.py watch 30                                    # 起動ログ。Starting shell... まで何も送らない
tools/r2p2dev.py run 'ls /lib' 'free'
tools/r2p2dev.py push local.rb /home/devtest/x.rb            # dfucli 経由。irb は使わない
```

- J2: 1=GND 2=SWCLK 3=SWDIO 4=UART_RX(GPIO1)←Probe TX 5=UART_TX(GPIO0)→Probe RX
- **`reset` や書き込みの直後にコンソールへ送らない。** Debug Probe が USB ごと固まり、抜き差しでしか戻らない
- この基板では openocd の halt が効かない。gdb は当面使えない。焼く・読む・書くは通る
- ハードを疑うときは、短いスクリプトを `push` して 1 トランザクションずつ成否を出し、書いたら読み戻す

## テスト

```console
# gem 単体（コンテナ内で）
docker compose -f docker/compose.yml run --rm shell rake 'test:gems:picoruby[picoruby-is31fl3729]'

# 型検査（Steepfile が **/sig/ を自動で拾う）
docker compose -f docker/compose.yml run --rm shell bundle exec steep check --log-level=fatal
```

## LED シミュレータ（実機なしで動かす）

ブラウザで実ドライバを動かし、16×16 の光り方を確認する。
[sim/README.md](sim/README.md) と [dev-docs/wasm-simulator/](dev-docs/wasm-simulator/)。

```console
rake sim:wasm               # フォント・描画 gem 入りの PicoRuby.wasm を作る（要 emsdk）
rake sim:test               # 中核のヘッドレス検証（ブラウザ不要）
rake sim:check              # ヘッドレス Chromium でページを操作して結果を報告
rake sim:check[one_dot]     # サンプル 1 つだけ
rake sim:server             # 手で見るとき → http://localhost:8080/sim/
```

`sim:check` は canvas を読み戻して **16×16 のテキスト**にするので、
目視ではなく機械的に判定できる。console 出力・ページエラーも報告し、
スクリーンショットは `tmp/browser-check/`（git 管理外）に残る。
ブラウザ用は**ファーム用とは別のイメージ**（`docker/browser.Dockerfile`）。

漢字・図形を出すには `rake sim:wasm` でローカルの wasm が要る
（stock の `@picoruby/wasm-wasi` に `picoruby-vram` / `-shinonome` が入っていないため）。
**emsdk はホストの `~/emsdk` をコンテナにマウントして使う**（イメージには入れない）。
`sim/vendor/` が無ければ CDN にフォールバックするので、ビルド無しでも動く。

## ハード仕様の正

| 順位 | 資料 |
|---|---|
| 1 | `tmp/picorubykaigi01-board/`（基板リポジトリの clone。`.kicad_pcb` / production / docs） |
| 1 | `ref/picorubykaigi01-board/production/r1/`（netlist / positions / 回路図 / BOM） |
| 1 | `ref/.../docs/PicoBoard_BOM_pin_assignment_20260824.xlsx`（`.kicad_pcb` から機械抽出） |
| 2 | `ref/external_info/data_sheet/IS31FL3729.pdf` |
| ✗ | `ref/.../docs/gpio_assignment.md` — **失効**。2026-08-18 の改訂で GPIO が入れ替わった |
| ✗ | `ref/.../docs/led_research_results.md` — 調査段階。LED は赤0603 → **白0402 に変更済み** |

抽出済みの要点は [dev-docs/led-matrix-gem/hardware.md](dev-docs/led-matrix-gem/hardware.md)。
`ref/` は git 管理外。

**間違えやすい点:**

- **SDB は GPIO24**（GPIO14 ではない）。**H にしてから 200µs 待って**最初の I2C
- **U11 は列が左右反転**（`cs = 17 - x`）。上半分 U10=0x34 / 下半分 U11=0x35
- **全点灯 + 音声で USB 500mA を超える。TPS2065 は 1A まで落ちないのでハードは守ってくれない**
- **IS31FL3729 は LGC を 0→1 にした直後の 1 トランザクションを必ず落とす**（データシート
  に無い。実チップで確認）。gem が `configure` で捨て読みを入れて吸収しているので、
  レジスタを直接叩くとき以外は気にしなくてよい
- **xlsx のボタン名は間違っている。** 正しいのはシルク印字: SW1=UP(GPIO17) /
  SW2=LEFT(18) / SW3=RIGHT(19) / SW4=DOWN(20) / SW5=B(21) / SW6=A(22)。
  xlsx は SW2〜SW6 を ↓ ← → A B としている。r1 で押して確認済み
- **MML のイベントは同じ時刻でも 1 つずつ Ruby で処理される**（debug ビルドで設定 1 つ 40〜60ms、`note_on` 20〜30ms）。
  複数トラックの先頭に設定（`s` `m` `@` `v` など）と音を続けて書くと、和音がばらける。設定のあとに短い休符を置く
- **スピーカーは PSG の左出力（GPIO10）だけ。** パンは `Speaker` が左いっぱい（`Board::PSG_SPEAKER_PAN`）にしている。
  音源（`PSG::Synth`）は設定を「送り主 × チャンネル」ごとに覚えるので、`synth.handle` で直接送った設定は
  `Speaker`（送り主 `:mml`）の音には効かない。3 声を v15 で重ねると出力は電源いっぱいまで振れる
- **GROVE1（J4）はピン順が逆。** Grove ケーブルをそのまま挿すと VCC と GND が入れ替わる

## 既知の落とし穴

実際に時間を溶かしたもの。同じ穴を掘り直さないこと。

### ビルド / テスト

- **`build/host` をホストとコンテナで共有している。** ホストで `rake` を起動すると
  `output here was built by another configuration, rebuilding it` が 1 行出るが、
  オブジェクトは消えない（前後で 90 個のまま）。ただし**無害ではない**: ホストで
  `rake sim:test` を走らせた直後のコンテナビルドが
  `Errno::ENOENT ... build/host/src/version.pi` で落ちた。`rm -rf build/host` で直る。
  **`rake docker:*` の背景実行では `rake aborted!` を必ず grep すること**——
  ログ末尾の `Artifacts copied` が無いのに古い ELF を焼いた
- **`picoruby-i2c` は posix ポートを持たない。** `spec.add_dependency 'picoruby-i2c'`
  を書くとホストテストのリンクが `I2C_write_timeout_us` 未定義で落ちる。
  ホストでテストする gem では宣言しないこと（`picoruby-adc` が `picoruby-gpio` で同じ判断）
- **`docs/testing-guide.md` の `test/mock/` は現在効かない。**
  `Picotest::Runner#run_test` はテストファイル 1 本しかターゲット VM へ埋め込まない。
  スタブは**テストファイル内に置く**
- コンテナはホストの uid/gid で動く。root 所有ファイルが出てきたら
  `docker compose run --rm --entrypoint chown shell -R 1000:1000 /work/...` で戻せる（sudo 不要）

### PicoRuby.wasm

- **`<script type="text/ruby">` は 1 つずつ別タスク**（`picorb_create_task`）になり、
  協調スケジューリングなので**実行順が保証されない**。依存があるなら 1 つに束ねる
- **JS ブリッジの引数は String / Integer / Float / nil / bool / JS::Object のみ。**
  Array や Hash を渡すと `TypeError`。interop ドキュメントの型対応表は `[]=` の話。
  `JS::Bridge.to_js` は使えるが要素ごとに push するので呼び出し回数が増える
- ブリッジは文字列を C 文字列として扱うので、**NUL を含むバイト列は途中で切れる**
- **存在しない JS 関数を呼んでも例外にならない。** console に
  `Method not found or not a function: ...` が出るだけなので、静かに失敗する
- **`JS.global.fetch` は `.then` ではなくブロックを取る。** Promise 一般は `.await` / `.then`
- **`addEventListener(..., sync: true)` の中では `await` できない**
  （`Cannot use asynchronous Task API during synchronous execution`）。
  autoplay ポリシー対応で同期リスナーが要るときは、await しない経路を選ぶ
- 例外は `rescue Exception` で捕まえる。**構文エラーは `ScriptError`** なので
  `rescue => e` では捕まらず、タスクが黙って死ぬ
- `require 'i2c'` のような組み込み gem 依存は、ブラウザや `bin/picoruby` では
  `LoadError` になる。`Kernel#require` を包んで握り潰す（picotest のランナーと同じ手）
- **`Machine` は wasm ビルドに無い**（`core` gembox 由来で、
  `build_config/picoruby-wasm.rb` は取り込んでいない）。`MIDIBASE::Router` などが
  `Machine.uptime_us` を呼ぶので、`performance.now()` で代替する
- 純 Ruby の gem（`picoruby-midibase` / `-mml` など）は**ソースを fetch して連結すれば
  stock パッケージで動く**。C 拡張（`psg` / `gpio` / `pwm` / `vram` / `shinonome`）は動かない
- **実機の USB シリアルをブラウザ（WebSerial）で使うときは、WSL から外しておく。**
  `usbipd attach` したままだと Windows のブラウザのポート一覧に出ない
- **`JS::WebSerial` の `binary_capture_*` は、`start_terminal_read`（xterm へ流す読み取り）と
  組でしか動かない。** `on_receive` で受けるなら、フレームは自前で切り出す（`sim/sim_device.rb`）

- **gem の初期化が 1 つ失敗すると、それより後ろの gem は全部初期化されない。しかも何も出ない。**
  `mrb_open()` は例外を抱えたままの VM を返し、`picorb_init` は NULL しか見ていない。wasm に入れた
  `picoruby-is31fl3729` は `require 'i2c'` で毎回こうなっている（ページはドライバのソースを自分で読むので困っていなかった）。
  後ろに足した gem の定数が「ビルドには入っているのに実行時に無い」ときはこれ。`build_config/picoruby-wasm.rb` では
  **`picoruby-is31fl3729` を最後に置く**
- **コードの欄の色付けは Prism**（`picoruby-syntax-highlight` の `SyntaxHighlight.tokenize`）。`rake sim:wasm` の wasm にだけ入っている。
  仕組みは [sim/README.md](sim/README.md) の「コードの色付け」

### Funicular（UI フレームワーク）

- stock パッケージに同梱（`build_config/picoruby-wasm.rb`）。追加ビルド不要
- **HTML タグ名はコンポーネントのメソッド名にできない**（`code` `audio` `select` など）
- `pre` は**タグ DSL に無い**。`tag("pre", ...)` を使う
- 子要素は**ブロックの戻り値ではなく副作用**で集まる（`ViewContext#capture`）。
  ヘルパーの中でタグを呼べば足りる。配列を組んで返す必要はない
- クラスメソッドからインスタンスを叩くなら `public :foo` が要る
- **速く変わるものは state に置かない。** canvas / テキストエリア / ログは `ref` で持つ
  （毎回 VDOM 差分が走る。テキストエリアを state にするとカーソルが飛ぶ）
- **`Task.new` のブロックは、書いた場所のオブジェクトを `self` として走らない。** インスタンス変数は読めず、自分のメソッドも
  呼べない（`NoMethodError` か、`@x` が nil で黙って何もしない）。`link = self` で渡して名前で呼ぶ。イベントリスナのブロックも同じ
- **`JS::WebSerial#close` は `on_receive` で読んでいるポートでは永久に戻らない**（読み取りループを止める仕組みが端末用の
  `start_terminal_read` にしか無い）。待たない `JS::WebSerial._close_port(raw)` を使う（`sim/sim_device.rb` の `close_without_waiting`）
- **`JS::Object` 同士の `==` は同じ JS オブジェクトでも偽になる**（参照 ID の比較で、Ruby 側から見るたびに新しい ID が付く）。
  見分けたければ JS オブジェクトにプロパティで印を付ける
- **WebSerial の再接続は `tools/browser-check/reconnect-check.cjs`**（偽の `navigator.serial`）で実機なしに確かめられる
- **ハートビートで「前回表示した文字列」と比べるなら、`<<` で伸ばした文字列を渡さない。**
  覚えておいた値も同じオブジェクトなので一緒に伸び、いつ比べても等しくなって表示が止まる。
  `@log = @log + out` のように新しい文字列を作る
- **Funicular がマウントする要素を、スクリプト読み込み時に掴んではいけない。**
  まだ存在しない。遅延取得する

### wasm の自前ビルド

- **emsdk はホストと同じパスにマウントする。** 場所が変わると emscripten が
  キャッシュを丸ごと捨てる（`config changed, clearing cache`）
- **compose の `${VAR:?}` は使わない。** ファイル全体が検証されるので、
  1 サービスのための必須変数が**全コマンド**を壊す
- `brotli` がビルドの最後に要る（イメージに追加済み）
- `mrbgems/picoruby-wasm/npm/` の成果物は全部 gitignore 済み。戻す必要はない
- **`python3 -m http.server` は `Cache-Control` を返さないので、ブラウザは `picoruby.wasm` / `picoruby.js` を自分の判断で
  持ち続ける。** `rake sim:wasm` のあと再読み込みしても古い wasm で動いた（色付けが出なかった）。`index.html` が読み込み前に
  `cache: 'no-cache'` で確認しに行くようにしてある。**ヘッドレスの `sim:check` は毎回まっさらなので、この種の問題は見つけられない**
- 静的サーバは `.wasm` に `application/wasm` を返すこと。
  でないとストリーミングコンパイルが拒否される

### シミュレータのコードは実機と同じでなければならない

**シミュレータ専用の構文は全面的に禁止。** サンプルがそのまま基板に載らなくなり、
シミュレータの存在意義が消える。`every(ms) { }` と、`sim/` にだけあった
`matrix` / `buttons` / `speaker` / `board` / `panel` で 2 度指摘を受けた。

- サンプルが呼べるものは**すべて `lib/picorubykaigi01.rb`**（ボードレイヤ）に置く
- `sim/` に置いてよいのは、実 gem と**同じ API を持つハードの代役**だけ
  （`I2C` / `GPIO` / `IRQ` / 仮想チップ）
- ループは実機と同じ `while true` + `sleep_ms`
  （`sleep_ms` はタスクを suspend してブラウザにイベントループを返すので固まらない）
- ペリフェラルの生成だけは両者で本当に違うので、**サンプルの外**で行う
  （実機は `Board.boot` の既定値、シミュレータは `sim_app.rb` が `$board` を用意）
- サンプルは `require 'picorubykaigi01'` から始める。実機では `/lib` から読み、
  ブラウザでは連結済みなので require シムが握り潰す。両方で正しい

**サンプルのコメントの書き方**（`sim/examples/` と `examples/` で共通。2026-09-22 に全部そろえた）:

- **`sim/examples/` は一般ユーザのためのもの。基板の検証用のコードは置かない**（`dev-docs/device-bringup/scripts/` へ）。
  数を増やしすぎない。ページの選択肢は「初めての人が読む順」に並べる（`SimApp::EXAMPLES`）。
  「ローカルの wasm が要る」という断り書きは付けない（自前の wasm をいずれ一般公開する前提）
- 冒頭は**題名 1 行 + 多くても 2 行**（操作方法、必要なもの）。仕組みや経緯の説明は書かない（README か dev-docs に置く）
- 説明は**その行の横**に短く書く。初めて出てくる API に 1 回だけ。同じ説明を繰り返さない
- `require` の並びは全サンプル同じ形。`GC.start` の説明は最初の 1 個の横にだけ（`# 読み込みで使ったメモリを片付ける`）、
  各 `require` の横にはそのファイルが何を使えるようにするか（`# LED マトリクス` `# ボタン` `# スピーカー`）
- コメントを直すときはコードを触らない。コメントを除いた行が元と一致することを確かめる

**ユーザのコードはトップレベルのメソッド（`run_user_source`）の中で `eval` する。** `SimApp` の中で `eval` すると、
ユーザの書いた `def` が `SimApp` に定義されて呼べず、**シミュレータでだけ** `NoMethodError` になった（実機では普通に動く構文）。
`sound_and_light.rb` がトップレベルの `def` を使っているので、`rake sim:check` がこの退行を拾う。

ユーザのコードは `Task` で走らせ、Run のたびに前を `terminate` する。
canvas はハートビートで仮想チップを映すので、コード側から再描画を指示しない。

### ボタン / 割り込み

- **ボタンはポーリングしない。** `picoruby-irq` のエッジ割り込みで受ける
  （`peripherals` gembox に含まれる。デバウンスは gem 内蔵）。
  ポーリングだと、短いクリックがサンプルの隙間に収まって**一度も観測されない**
- 押下はキューに積んで `take_press` / `each_press` で取り出す。
  ループの速さに関係なく 1 回の押しが 1 回として届く
- オートリピートは `Buttons` に入れずループ側で作る
- **シェルで流したスクリプトの GPIO 割り込みは、終わっても登録が残る。** 同じピンは
  新しい登録で置き換わるように直したが、**別のピンの登録は溜まる**（最大 16 個）。
  いろいろなピンを使うスクリプトを続けて流すときは、あいだに `tools/r2p2dev.py reset` を挟む
- `picoruby-irq` のデバウンスは作り直した（元は離すときのチャタリングが押下として届いた）。
  どちらも upstream の問題として [dev-docs/upstream-issues.md](dev-docs/upstream-issues.md) に記録
- **ボタンの代わりに GPIO を自分で動かして割り込みを試せる。** 出力にしたピンでも入力バッファが
  生きているので、同じピンの割り込みが立つ。空きは GPIO15、緑 LED の GPIO16 も使える

### 実機（Pico 2 W）

痛い目を見た順。詳細は [dev-docs/device-bringup/](dev-docs/device-bringup/)。

- **`require` 1 回の固定費が約 28KB**で、GC を呼ばないと返ってこない。
  コンパイルにはソースの約 6 倍の**連続**領域が要り、常駐は約 5 倍。
  **サンプルは使うペリフェラルを自分で require する**
  （`require 'picorubykaigi01/led_matrix'`）。隠さないこと——
  何を読み込んでいるかはサンプルが教えることの一部で、実費でもある。
  `Board` 側は構築だけ遅延させる（使わないハードを起こさない）
- **サンプルは require 1 本ごとに `GC.start` を呼ぶ。** `require.rb` は
  Sandbox を回収しないので、1 本 28KB が積み上がる。まとめて最後に呼んでも
  `max_free` は戻らない（12,328 のまま）。1 本ごとなら 20,736 まで増える
- **ファームは変わったファイルだけ書く。** `/etc/picorubykaigi01-files` に
  中身のハッシュを置いて比べる。`/lib` は更新されるが、
  **`/home/examples` は一度置いたら二度と触らない**（ユーザの編集物なので）。
  サンプルを直したら `tools/r2p2dev.py wipefs` で消してから焼く
- **openocd の `reset` を使わない。** SYSRESETREQ はペリフェラルを戻さないので、
  USB が半死のまま R2P2 が起動してプロンプトまで来ない。
  `r2p2dev.py reset` はウォッチドッグで落とす
- **prod は stdio が丸ごと無効**（`pico_enable_stdio_usb 0` / `_uart 0`）。
  `printf` はどこにも出ない
- **`r2p2dev.py` が出す `$> ...` はボードの応答ではない。** 出力が空＝ボードが無言
- **r1 基板では SWD の halt が効かない**（両コアが `unknown`）。メモリの読み書きと
  `program` は通る。ウォッチドッグ再起動は halt を `catch` で包んで書く
  （`flash.sh` / `r2p2dev.py` は対応済み）。書き込み後は UART に
  `installed /etc/picorubykaigi01-files` が出るまで SWD を触らない
- **`r2p2dev.py reset` の直後に `run` しない。** ターゲットの起動中にプローブの
  UART へ送ると Debug Probe が USB ごと固まり、**抜き差しでしか戻らない**
  （usbipd の detach/attach では戻らない）。起動ログが流れ終わってから叩く
- **書き込みの直後に SWD でフラッシュを触らない。** 起動中のファームが
  `/lib` を書いている最中に消すと、書きかけが残って USB が死ぬ。
  `r2p2dev.py` の `reset` / `wipefs` はプロンプトが返るまで待つ
- 戻せなくなったら **BOOTSEL** → `tools/r2p2dev.py recover`
- **debug ビルドは `-O0`、prod は `-O2`。** r1 は UART コンソールのために debug しか使わないので、
  時間に追われる処理（PSG の core1 など）は debug でだけ間に合わなくなる。締め切りのある関数には
  `__attribute__((optimize("O2")))` を付け、RAM に置く（`.time_critical`）。2 つのコアは同じフラッシュから
  命令を取るので、core0 が Ruby を回しているあいだ core1 のフラッシュ上のコードは 3 倍遅くなる
- **SDK の `static inline`（`dma_channel_is_busy` など）は `-O0` では関数として残り、フラッシュに置かれる。**
  RAM に置いた関数から呼ぶなら、レジスタを直接触る
- **SWD で変数を読み書きする番地は、ビルドのたびに `nm` で取り直す。** 古い番地にゼロを書いて基板を固めた。
  openocd で値を見るのは `echo "[read_memory ADDR 32 N]"`（`mdw` は `-c` では何も出さない）。halt は要らない
- **RP2350 の DMA `TRANS_COUNT` は上位 4 ビットが MODE。** RP2040 の例が書く
  `0xffffffff` は RP2350 では **ENDLESS**（カウントを減らさない）になり、
  バッファは埋まるのにカウンタが 0 のままになる。`0x0fffffff` を使う
- **PIO のピン方向はステートマシン間で共有される。** 受信側で pindirs を
  入力にすると、同じピンを使う送信側の出力が消える
- **埋まっているハードウェアアラームを `hardware_alarm_claim()` すると panic する。**
  0 は `picoruby-machine` のティック、1 と 2 は `picoruby-psg`、
  3 は SDK の既定アラームプール。`hardware_alarm_claim_unused()` で取る
- **GCC の "two or more data types in declaration specifiers" が健全な `bool` を
  指したら、手前の宣言が閉じていない。** 「未知の型」に見えるエラーも同じ。
  同じファイルの別の場所で同じ型が通っているなら、型の問題ではない
- **Ruby 側の無い gem でも `_gem_init` / `_gem_final` は要る**（リンクで落ちる）。
  `ports/rp2040/*.c` は CMake が自動で拾うので `CMakeLists.txt` は触らなくてよい

### その他

- `bin/picoruby` で相対パスを `load` するには `$LOAD_PATH = ["."]` が要る
- **トップレベル `def` は public**（CRuby は自動で private にするが mruby はしない）。
  `private` を**明示すれば**効く。`private` / `private :name` / `private def` /
  `protected` はいずれも呼び出しを止め、`send` は CRuby 同様に迂回できる。
  ただし `respond_to?` は可視性を見ず private でも true を返し、
  `Object.private_method_defined?` は存在しない
- ESM の `import` は `NODE_PATH` を見ない。`playwright install` は
  インストールしたユーザの HOME に置く（`PLAYWRIGHT_BROWSERS_PATH` で固定した）

## upstream との関係

このリポジトリは picoruby のフォークなので、**upstream のファイルへの変更は最小限に**。

**全部の一覧と理由は [dev-docs/upstream-changes.md](dev-docs/upstream-changes.md)。**
以下は要約:

- `Rakefile` — `tasks/docker.rake` と `tasks/sim.rake` の load 2 行
- `build_config/r2p2-picoruby-pico2{,_w}.rb` — `conf.gem core:` 各 1〜2 行
  （`picoruby-is31fl3729` と `picoruby-pio-uart`）
- `build_config/r2p2-picoruby-pico2_w.rb` — `networking` / `picoruby-ble` /
  `picoruby-ble-uart` / `picoruby-keyboard` を**外した**。これで起動直後のヒープが
  290KB → 220KB になり、ボードライブラリが読めるようになる
  （[dev-docs/device-bringup/require-memory.md](dev-docs/device-bringup/require-memory.md)）
- `mrbgems/picoruby-r2p2/ports/rp2040/fault_handler.c` — フォールト時に
  ロックアップせず再起動する
- `mrbgems/picoruby-r2p2/ports/rp2040/main.c` / `cmake/CMakeLists.txt` — `/lib` と
  `/home/examples` を書き出す処理の呼び出しと生成ステップ
- `mrbgems/picoruby-uart/{include/uart.h,ports/rp2040/uart.c}` と
  `mrbgems/picoruby-irq/include/irq.h` — **`UART` に PIO のユニットを足した**
  （`UART.new(unit: :PIO_UART0, ...)`）。別クラスにしないのは、この基板で
  覚えたことが素の R2P2 で通じるようにするため
- `mrbgems/picoruby-machine/ports/rp2040/machine.c` — **`SLEEP_EN0/1` を絞る代入を消した。** 元は CPU が眠る
  （タスクが全部 `sleep_ms` などで待つ）たびに PWM / DMA / PIO / I2C / SPI / ADC が止まり、
  スピーカーの「ざらざら」の原因だった（[dev-docs/audio-quality/report.md](dev-docs/audio-quality/report.md)）
- `mrbgems/picoruby-littlefs/ports/rp2040/flash_hal.c` と `mrbgems/picoruby-psg/ports/rp2040/psg_port.c` —
  **フラッシュに書くあいだ core1（PSG）を待たせる。** 元は PSG を一度使ったあとにファイルを書くと core1 が固まった
- `mrbgems/picoruby-psg/` — キャリアを 132kHz に、DMA 2 チャンネルの交互連鎖、出力を中央基準に、三角波とエンベロープの修正。
  **core1 の音声処理は RAM に置き、debug ビルドでも `-O2`**（`PSG_HOT`）。元は各音のあたまにノイズが入った
- `mrbgems/picoruby-vram/` — 8bit 階調（`layout: :gray8`）
- `mrbgems/picoruby-irq/` — エッジのデバウンスを作り直し、同じピンの登録を置き換えにした（PR を送る前提。
  問題の記録は [dev-docs/upstream-issues.md](dev-docs/upstream-issues.md)）

新規ディレクトリ（`mrbgems/picoruby-is31fl3729/`、`mrbgems/picoruby-pio-uart/`、`mrbgems/picoruby-syntax-highlight/`、
`sim/`、`dev-docs/`、
`tools/`、`docker/`）は追加なので衝突しない。
`mrbgems/` **自体はサブモジュールではない**（サブモジュールは中の特定 gem だけ）。

⚠️ `tasks/picoruby/r2p2.rake` は `%w[pico pico_w pico2 pico2_w]` を決め打ちで
ループしてタスクを生成する。独自ボード名を足すにはここに手を入れる必要がある（未対応）。

## ドキュメント

| 場所 | 内容 |
|---|---|
| [dev-docs/](dev-docs/) | 計画とハード仕様の索引 |
| [dev-docs/board-gems/](dev-docs/board-gems/) | 基板の全機能を Ruby から触るための gem 棚卸し |
| [dev-docs/led-matrix-gem/](dev-docs/led-matrix-gem/) | LED ドライバの実装計画とハード仕様 |
| [dev-docs/wasm-simulator/](dev-docs/wasm-simulator/) | ブラウザシミュレータの計画と完了レポート |
| [dev-docs/device-bringup/](dev-docs/device-bringup/) | 実機で踏んだ穴。**Debug Probe だけで触る手順書**、WSL からの書き込み、`require` の費用 |
| [dev-docs/grove-link/](dev-docs/grove-link/) | 基板 2 枚を GROVE-B で繋ぐ。PIO で UART を作る |
| [docker/README.md](docker/README.md) | ビルド環境の詳細 |
| [sim/README.md](sim/README.md) | シミュレータの使い方 |
| [examples/](examples/) | **実機専用**サンプル（シミュレータに無いハードを使うもの） |

## 進捗

- ✅ Docker ビルド環境、`rake docker:*`、SWD 書き込み
- ✅ `mrbgems/picoruby-is31fl3729`（23 テスト / 60 アサーション）。r1 実チップで
  0x34 / 0x35 とも応答。LGC の落とし穴を見つけて吸収済み
- ✅ `mrbgems/picoruby-pio-uart`（PIO + DMA のエンジン。`UART` の `:PIO_UART0`
  ユニットとして見える。`gets` / `irq` まで実機ループバックで検証済み）
- ✅ ブラウザシミュレータ（LED / ボタン / 音声）と検証環境。UI は Funicular。コードの欄は Prism で色付け
- ✅ `lib/picorubykaigi01.rb`（ボードレイヤ: Board / LedMatrix / Buttons / Speaker）
- ✅ フォント描画（`picoruby-shinonome`）と VRAM 描画 API。16×16 に漢字が出る
- ✅ `picoruby-vram` に 8bit 階調（`layout: :gray8`）。線も文字も明るさを持てる
- ✅ 明るさは見た目に比例（`LedMatrix#duty_of` でガンマ 2.0。テーブル無し、
  `set` の 1 箇所だけ。シミュレータは描画時に平方根で戻す）
- ✅ `/lib` への配布 — ファームが内蔵し初回起動時に書き出す（UF2 1本。実機未検証）
- ✅ Pico 2 W 実機で `require 'picorubykaigi01'` → `/home/examples/status_led.rb` が動く
- ✅ ファーム更新で `/lib` を配り直す（中身のハッシュで判定。サンプルは触らない）
- ✅ GROVE-B の基板間リンク — **普通の `UART`**（`unit: :PIO_UART0`）。
  受信は DMA のリングバッファ。ストレートケーブルで繋がる。
  ループバック検証済み、2 枚での確認は基板待ち
- ✅ スピーカーの音（PSG）。ざらざら・音程・三角波を直した。各音のあたまのノイズも直した（ADC の記録と耳で確認）。
  経緯と測定は [dev-docs/audio-quality/report.md](dev-docs/audio-quality/report.md)。基板自身の ADC で出力を録る
  `picoruby-adc-capture`（J6 → GPIO26）と `tools/adc_capture_dump.py` が検証に使える
- ⬜ シミュレータを GitHub Pages で公開する（Actions で `rake sim:wasm` 相当を組んで `sim/` を出す）。
  **リポジトリを別の Organization に移してからやる**（2026-09-21 の決定）。それまで `sim/vendor/` は git 管理外のままで、
  色付け・漢字は `rake sim:wasm` をした環境でだけ出る（無ければ CDN の stock で、色なし・漢字なしで動く）
- ⬜ GROVE-A センサ、サンプルプログラムの拡充
- ✅ r1 実基板に `pico2` debug ビルドを SWD で焼き、UART で起動ログを確認
- ✅ r1 で LED マトリクス（向き・列反転・階調）とスピーカー（`melody.rb`）が動く
- ✅ r1 でボタン 6 個とステータス LED（名前はシルク印字に合わせて修正済み）
- ✅ r1 の GROVE1（J4 = I2C1）に M5Stack CardKB（0x5F）を**逆ケーブル**で繋ぎ、
  キー入力が読めた
- ✅ r1 の GROVE2（J5）: 信号線 2 本をジャンパでつなぎ、導通（両方向）と
  PIO UART（TX=GPIO28 → RX=GPIO29、0〜255 の全バイト）を確認。
  ADC とピン順（同じ部品なので逆の可能性が高い）は未確認
- ✅ R2P2 コンソールを UART にも出す（`R2P2_CONSOLE_UART=1`。r1 は USB を手で直したが、Probe の UART からも同時に叩ける）。
  `R2P2_PORT=/dev/ttyACM0 tools/r2p2dev.py run ...` でプローブの UART から叩ける
- ✅ シミュレータのページから USB で実機に送って実行（[実機で実行]、WebSerial + PicoModem）。
  USB を直した基板で確認。何度も実行すると実機が応答しなくなる件は、PSG（core1）を止めずにフラッシュへ書いていたのが原因で、修正済み
  （[dev-docs/upstream-issues.md](dev-docs/upstream-issues.md) の 4）
- ⬜ J1（ブレッドボード用 2×10 ヘッダ）の疎通確認。手順とスクリプトは
  [dev-docs/device-bringup/scripts/header_check.rb](dev-docs/device-bringup/scripts/header_check.rb)
- ⬜ 基板用 build_config（`tasks/picoruby/r2p2.rake` の
  ボード名ループに手を入れる必要がある）
