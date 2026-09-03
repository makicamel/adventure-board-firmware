# picorubykaigi01-board-firmware

PicoRuby のフォーク。**picorubykaigi01-board**（RP2350A / 16×16 LED マトリクス /
音声 / ボタン / GROVE、PicoRubyKaigi の学習用配布基板）のファームウェアを作る。

基板は製造中。当面の開発機は **Raspberry Pi Pico 2 W**。

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
rake sim:check[l_shape]     # サンプル 1 つだけ
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
| 1 | `ref/picorubykaigi01-board/production/r1/`（netlist / positions / 回路図 / BOM） |
| 1 | `ref/.../docs/PicoBoard_BOM_pin_assignment_20260824.xlsx`（`.kicad_pcb` から機械抽出） |
| 2 | `ref/external_info/data_sheet/IS31FL3729.pdf` |
| ✗ | `ref/.../docs/gpio_assignment.md` — **失効**。2026-08-18 の改訂で GPIO が入れ替わった |
| ✗ | `ref/.../docs/led_research_results.md` — 調査段階。LED は赤0603 → **白0402 に変更済み** |

抽出済みの要点は [dev-docs/led-matrix-gem/hardware.md](dev-docs/led-matrix-gem/hardware.md)。
`ref/` は git 管理外。

**間違えやすい 3 点:**

- **SDB は GPIO24**（GPIO14 ではない）。**H にしてから 200µs 待って**最初の I2C
- **U11 は列が左右反転**（`cs = 17 - x`）。上半分 U10=0x34 / 下半分 U11=0x35
- **全点灯 + 音声で USB 500mA を超える。TPS2065 は 1A まで落ちないのでハードは守ってくれない**

## 既知の落とし穴

実際に時間を溶かしたもの。同じ穴を掘り直さないこと。

### ビルド / テスト

- **`build/host` をホストとコンテナで共有している。** ホストで `rake` を起動すると
  `output here was built by another configuration, rebuilding it` が 1 行出るが、
  オブジェクトは消えない（前後で 90 個のまま）。**無害**
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

### Funicular（UI フレームワーク）

- stock パッケージに同梱（`build_config/picoruby-wasm.rb`）。追加ビルド不要
- **HTML タグ名はコンポーネントのメソッド名にできない**（`code` `audio` `select` など）
- `pre` は**タグ DSL に無い**。`tag("pre", ...)` を使う
- 子要素は**ブロックの戻り値ではなく副作用**で集まる（`ViewContext#capture`）。
  ヘルパーの中でタグを呼べば足りる。配列を組んで返す必要はない
- クラスメソッドからインスタンスを叩くなら `public :foo` が要る
- **速く変わるものは state に置かない。** canvas / テキストエリア / ログは `ref` で持つ
  （毎回 VDOM 差分が走る。テキストエリアを state にするとカーソルが飛ぶ）
- **Funicular がマウントする要素を、スクリプト読み込み時に掴んではいけない。**
  まだ存在しない。遅延取得する

### wasm の自前ビルド

- **emsdk はホストと同じパスにマウントする。** 場所が変わると emscripten が
  キャッシュを丸ごと捨てる（`config changed, clearing cache`）
- **compose の `${VAR:?}` は使わない。** ファイル全体が検証されるので、
  1 サービスのための必須変数が**全コマンド**を壊す
- `brotli` がビルドの最後に要る（イメージに追加済み）
- `mrbgems/picoruby-wasm/npm/` の成果物は全部 gitignore 済み。戻す必要はない
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

ユーザのコードは `Task` で走らせ、Run のたびに前を `terminate` する。
canvas はハートビートで仮想チップを映すので、コード側から再描画を指示しない。

### ボタン / 割り込み

- **ボタンはポーリングしない。** `picoruby-irq` のエッジ割り込みで受ける
  （`peripherals` gembox に含まれる。デバウンスは gem 内蔵）。
  ポーリングだと、短いクリックがサンプルの隙間に収まって**一度も観測されない**
- 押下はキューに積んで `take_press` / `each_press` で取り出す。
  ループの速さに関係なく 1 回の押しが 1 回として届く
- オートリピートは `Buttons` に入れずループ側で作る

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
- 戻せなくなったら **BOOTSEL** → `tools/r2p2dev.py recover`

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
現状の変更は次だけ:

- `Rakefile` — `tasks/docker.rake` と `tasks/sim.rake` の load 2 行
- `build_config/r2p2-picoruby-pico2{,_w}.rb` — `conf.gem core:` 各 1 行
- `build_config/r2p2-picoruby-pico2_w.rb` — `networking` / `picoruby-ble` /
  `picoruby-ble-uart` / `picoruby-keyboard` を**外した**。これで起動直後のヒープが
  290KB → 220KB になり、ボードライブラリが読めるようになる
  （[dev-docs/device-bringup/require-memory.md](dev-docs/device-bringup/require-memory.md)）
- `mrbgems/picoruby-r2p2/ports/rp2040/fault_handler.c` — フォールト時に
  ロックアップせず再起動する
- `mrbgems/picoruby-r2p2/ports/rp2040/main.c` / `cmake/CMakeLists.txt` — `/lib` と
  `/home/examples` を書き出す処理の呼び出しと生成ステップ
- `docker/build.sh` — dist に最新の 1 本だけ置く

新規ディレクトリ（`mrbgems/picoruby-is31fl3729/`、`sim/`、`dev-docs/`、
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
| [dev-docs/device-bringup/](dev-docs/device-bringup/) | 実機で踏んだ穴。WSL からの書き込みとデバッグ、`require` の費用 |
| [docker/README.md](docker/README.md) | ビルド環境の詳細 |
| [sim/README.md](sim/README.md) | シミュレータの使い方 |
| [examples/](examples/) | **実機専用**サンプル（シミュレータに無いハードを使うもの） |

## 進捗

- ✅ Docker ビルド環境、`rake docker:*`、SWD 書き込み
- ✅ `mrbgems/picoruby-is31fl3729`（20 テスト / 52 アサーション、実チップ未検証）
- ✅ ブラウザシミュレータ（LED / ボタン / 音声）と検証環境。UI は Funicular
- ✅ `lib/picorubykaigi01.rb`（ボードレイヤ: Board / LedMatrix / Buttons / Speaker）
- ✅ フォント描画（`picoruby-shinonome`）と VRAM 描画 API。16×16 に漢字が出る
- ✅ `picoruby-vram` に 8bit 階調（`layout: :gray8`）。線も文字も明るさを持てる
- ✅ `/lib` への配布 — ファームが内蔵し初回起動時に書き出す（UF2 1本。実機未検証）
- ✅ Pico 2 W 実機で `require 'picorubykaigi01'` → `/home/examples/status_led.rb` が動く
- ✅ ファーム更新で `/lib` を配り直す（中身のハッシュで判定。サンプルは触らない）
- ⬜ GROVE / ステータス LED、サンプルプログラムの拡充
- ⬜ 基板用 build_config（`USE_WIFI` を外す。`tasks/picoruby/r2p2.rake` の
  ボード名ループに手を入れる必要がある）、実基板ブリングアップ
