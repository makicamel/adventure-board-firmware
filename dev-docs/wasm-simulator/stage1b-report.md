# Stage 1b 完了レポート — ボタンと音声

計画: [stage1b-plan.md](stage1b-plan.md)

## 1. 結論

**完了。ヘッドレス 44/44、ブラウザ全 11 サンプル・エラーゼロ。**

計画で挙げた「ボードレイヤを本物として書く」方針が通り、
**ブラウザで動かしているコードがそのまま基板に載る**形になった。

## 2. 忠実度（実測）

| | ブラウザで走るもの | 代替されるもの |
|---|---|---|
| **LED** | ドライバ（`picoruby-is31fl3729`）、`LedMatrix` | チップ（仮想 IS31FL3729） |
| **ボタン** | `Buttons`（負論理・チャタリング除去） | `GPIO` |
| **音声** | `MIDIBASE::MML::Parser` / `Sequence` / `Player` / `Router`、`Speaker` | **音源のみ**（PSG → `JS::WebAudio::Synth`） |

音声はこうなった:

```
MML テキスト
  → MIDIBASE::MML::Parser / Sequence / Player   ← 実物（純 Ruby）
  → MIDIBASE::Router                            ← 実物
  → JS::WebAudio::Synth                         ← PSG の代わり（stock パッケージ）
```

**差し替わるのは音源だけ**で、そこはまさに C 拡張で動かせない部分。

## 3. 成果物

```
lib/picorubykaigi01.rb    ボードレイヤ（実機にも載る）
                          Board / LedMatrix / Buttons / Speaker
sim/sim_audio.rb          Machine 代替 / NoteLog / WebAudioSpeaker
sim/sim_panel.rb          I2C / GPIO / VirtualIS31FL3729 / Panel（SDB も再現）
sim/examples/             11 本
```

`sim/index.html` は 14 本のソースを fetch して連結する
（`sim_panel` → midibase 6 本 → midibase-mml 4 本 → ドライバ → ボードレイヤ →
`sim_audio` → `sim_ui`）。

## 4. 検証結果

### ヘッドレス `rake sim:test` — 44/44

LED 系（1〜8）に加えて:

| # | 内容 |
|---|---|
| 9 | ボタンが負論理で読めること、**2 回一致で確定するチャタリング除去**、エッジ検出、同時押し、6 名すべてが自分のピンに対応すること |
| 10 | **MML が `C4 D4 E4` の note_on として出てくること**（実パーサ） |
| 11 | `Speaker` が sink へ流すこと、**アンプの SD ピンが無音時 L、発音時 H** になること、`stop` が All Notes Off を送ること |
| 12 | ノートログが音名・経過時間・velocity 0 = note off を正しく読むこと |

### ブラウザ `rake sim:check`

- **ボタン**: 画面ボタン長押しでドットが移動、**キーボード**（矢印キー）でも同じ、B 押下中だけ十字が出る
- **ループ**: `spinner` が 1.2 秒で 15 回（80ms 間隔どおり）
- **音声**: `melody` が `C C G G A A G` を正しい間隔で 28 イベント、
  `sound_and_light` は音とパネルが同時に動く
- console エラー / ページエラー / リクエスト失敗: **すべて 0**

## 5. 実装中に見つけて直したこと

### 5-1. `while` の中で作るブロックは変数を共有する

Ruby の `while` はスコープを作らないので、ループ内で作った 6 個のリスナーが
同じ `pin` 変数を掴み、**全ボタンが最後の pin=22 を送っていた**。
バインドをメソッドに切り出して、引数で新しいスコープを作って解決。

ヘッドレスブラウザが無ければ気づけなかった類のバグ。

### 5-2. `Machine` が wasm ビルドに無い

`MIDIBASE::Router` は `Machine.uptime_us` でタイムスタンプを打つが、
`picoruby-machine` は `core` gembox にあり、`build_config/picoruby-wasm.rb` は
それを取り込んでいない。`performance.now()` で代替した。

### 5-3. ノートログが更新されない

メロディは `Player#start` が作る**独立したタスク**で数秒かけて鳴る。
他に何も走っていなければ再描画の機会がないので、ログ専用のハートビートを足した。

### 5-4. `sync: true` のリスナーは `await` できない

ブラウザの autoplay ポリシーは AudioContext の resume を
**ジェスチャ自身のスタック上**で行うことを要求する。それには同期リスナーが要るが、
同期実行中に task は suspend できない
（`RuntimeError: Cannot use asynchronous Task API during synchronous execution`）。
`Synth#resume` は promise を await するので使えず、AudioContext を直接 resume した。

## 6. 設計上の判断

### ボードレイヤを `lib/picorubykaigi01.rb` に置いた

`Buttons` も `Speaker` もシミュレータ専用ではなく実機で動くコード。
`sim/` に置くと二重管理になるので、**ボードサポートの本物として書き**、
シミュレータはそれをファイルとして読む。
[../board-gems/README.md](../board-gems/README.md) §3 の
「gem にせず littlefs 上のソースにする」という決定とも整合する。

ハードは `new` せず**注入**を受ける形にした。
基板では実ペリフェラル、ブラウザではスタブで、それ以外は同じコードが動く。

### ボタンはオートリピートを持つ

押している間ずっと `pressed?` が真なので、ループ内でそのまま使うと
**1 tick ごとに 1 歩進んでしまう**（60ms ループなら 300ms 押しただけで 5 歩）。
実際に触って「数ドットまとめて進む」と指摘を受けたため、
`repeat?` を足した。押した瞬間に 1 回、少し置いてから一定間隔で繰り返す
（キーボードと同じ）。カーソル移動は `repeat?`、
「押している間だけ効かせたいもの」は `pressed?` と使い分ける。

ミリ秒ではなく `update` の呼び出し回数で数えている。時計に依存せずに済み、
速度は呼び出し側のループがそのまま決める。

### `every(ms)` は `setInterval` ではない

毎回 `setTimeout` を張り直す。遅いブロックが積み上がらない。
呼ぶ直前に `buttons.update` を回すので、実機のメインループと同じ形になる。

### ノートログを router の 2 つ目の sink にした

ヘッドレスでは音が聞けないので、**これが音声を検証可能にしている唯一の手段**。
同時に、曲を書くときに何がいつ鳴るか見えるので実用性もある。

## 7. 既知の制限

| 項目 | 内容 |
|---|---|
| 演奏テンポ | ブラウザでは実測が譜面より 1〜2 割速い。`InternalClock` が `sleep_ms` 刻みで待つため、協調スケジューリング下では誤差が出る。実機では PSG が自走するので事情が異なる |
| フォント・図形 | `picoruby-shinonome` / `picoruby-vram` は C 拡張で stock の wasm に無い（Stage 2） |
| 音色 | WebAudio のオシレータで、PSG の音とは違う |
| 上下・左右の向き | 実機で 1 ドット点灯するまで未確定 |

## 8. 次

**UI の Funicular 移行。** `picoruby-funicular` は stock パッケージに入っており
（`build_config/picoruby-wasm.rb`）、追加ビルドは要らない。
今 `sim_ui.rb` が手書きしている DOM グルーが state の派生になる。
16×16 の描画は canvas のまま `ref` で掴む方針（256 個の div を VDOM で
毎フレーム差分更新するのはコストが読めないため）。
