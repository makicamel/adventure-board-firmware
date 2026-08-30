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
rake sim:test               # 中核のヘッドレス検証（ブラウザ不要）
rake sim:check              # ヘッドレス Chromium でページを操作して結果を報告
rake sim:check[l_shape]     # サンプル 1 つだけ
rake sim:server             # 手で見るとき → http://localhost:8080/sim/
```

`sim:check` は canvas を読み戻して **16×16 のテキスト**にするので、
目視ではなく機械的に判定できる。console 出力・ページエラーも報告し、
スクリーンショットは `tmp/browser-check/`（git 管理外）に残る。
ブラウザ用は**ファーム用とは別のイメージ**（`docker/browser.Dockerfile`）。

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
- **`JS.global.fetch` は `.then` ではなくブロックを取る。** Promise 一般は `.await` / `.then`
- 例外は `rescue Exception` で捕まえる。**構文エラーは `ScriptError`** なので
  `rescue => e` では捕まらず、タスクが黙って死ぬ
- `require 'i2c'` のような組み込み gem 依存は、ブラウザや `bin/picoruby` では
  `LoadError` になる。`Kernel#require` を包んで握り潰す（picotest のランナーと同じ手）

### その他

- `bin/picoruby` で相対パスを `load` するには `$LOAD_PATH = ["."]` が要る
- ESM の `import` は `NODE_PATH` を見ない。`playwright install` は
  インストールしたユーザの HOME に置く（`PLAYWRIGHT_BROWSERS_PATH` で固定した）

## upstream との関係

このリポジトリは picoruby のフォークなので、**upstream のファイルへの変更は最小限に**。
現状の変更は次だけ:

- `Rakefile` — `tasks/docker.rake` と `tasks/sim.rake` の load 2 行
- `build_config/r2p2-picoruby-pico2{,_w}.rb` — `conf.gem core:` 各 1 行

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
| [docker/README.md](docker/README.md) | ビルド環境の詳細 |
| [sim/README.md](sim/README.md) | シミュレータの使い方 |

## 進捗

- ✅ Docker ビルド環境、`rake docker:*`、SWD 書き込み
- ✅ `mrbgems/picoruby-is31fl3729`（20 テスト / 52 アサーション、実チップ未検証）
- ✅ ブラウザシミュレータ Stage 1 と検証環境
- ⬜ `/lib/picorubykaigi01.rb`（表示層。**gem にせず littlefs 上のソースにする** —
  ユーザが読んで直せるように。[dev-docs/board-gems/](dev-docs/board-gems/) §3）
- ⬜ サンプルプログラム群
- ⬜ 基板用 build_config、実基板ブリングアップ
