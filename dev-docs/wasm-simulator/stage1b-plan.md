# Stage 1b 実装計画 — ボタンと音声

親計画: [README.md](README.md) / 前段: [stage1-report.md](stage1-report.md)

## 1. 何をやるか

シミュレータで**ボタンと音声**も扱えるようにする。
そうすると「触ってすぐ光る・鳴る・反応する」という基板のコンセプトが、
基板なしで最後まで作り込める。

## 2. 忠実度がどこまで出るか（調べた結果）

LED は実ドライバをそのまま動かせた。ボタンと音声はそれぞれ事情が違う。

| | 実物 | ブラウザで走るもの | 忠実度 |
|---|---|---|---|
| **ボタン** | GPIO17〜22、10kΩ プルアップ、負論理 | `GPIO` のスタブ。**ボードレイヤの `Buttons` は実コードがそのまま動く** | ◎ |
| **音声（MML）** | MML → MIDI イベント → PSG → PWM → PAM8302A | **`picoruby-midibase` と `picoruby-midibase-mml` は純 Ruby**なので、パーサもシーケンサも実物が動く | ○ |
| **音声（発音）** | PSG（C 拡張） | `JS::WebAudio::Synth`。**stock の `@picoruby/wasm-wasi` に入っている**（`picoruby-wasm/mrblib/webaudio*.rb`） | 代替 |

つまり音声は

```
MML テキスト
  → MIDIBASE::MML::Parser / Sequence / Player   ← 実物（純 Ruby、fetch して読む）
  → MIDIBASE::Router                            ← 実物
  → WebAudio::Synth                             ← stock パッケージ。実際に音が出る
```

**差し替わるのは PSG（音源）だけ**で、そこはまさに C 拡張で動かせない部分。
置き換えの継ぎ目として妥当。

確認済みの事実:

- `midibase` 6 ファイル + `midibase-mml` 4 ファイル = 1533 行、外部依存は `require "midibase"` のみ
- `WebAudio::Synth#initialize` が `MIDIBASE::VoiceAllocator` を使うのは**インスタンス生成時**で、
  クラス定義時ではない。だから midibase を先に読めば stock パッケージのままで動く
- `picoruby-psg` / `picoruby-gpio` / `picoruby-pwm` はいずれも C 拡張で stock には無い

## 3. 設計上の方針転換 — ボードレイヤを本物として書く

ここが今回の要。

`Buttons` と `Speaker` は**シミュレータ専用コードではなく、実機でも動くボードレイヤ**。
なので `sim/` の中ではなく、**`lib/picorubykaigi01.rb` に本物として書き**、
シミュレータはそれを（実ドライバと同じように）ファイルとして読む。

[../board-gems/README.md](../board-gems/README.md) §3 の決定どおり、
このファイルは gem にせず littlefs 上のソースとして配る。
つまり**シミュレータで書いたものがそのまま基板へ載る**。

現在 `sim/sim_panel.rb` にある `LedMatrix` もここへ移す。

```
lib/picorubykaigi01.rb     ← ボードレイヤ（実機にも載る本物）
  LedMatrix / Buttons / Speaker / Board

sim/sim_panel.rb           ← シミュレータ専用のスタブ
  I2C / GPIO / VirtualIS31FL3729 / Panel
sim/sim_audio.rb           ← 音声バックエンド（WebAudio 側）
sim/sim_ui.rb              ← 画面
```

ボードレイヤはハードを直接 `new` せず**注入**を受ける形にする。
そうしないと実機用の `I2C.new(unit: :RP2040_I2C0, ...)` がブラウザで書けない。

## 4. 実装項目

### 4-1. ボタン

- `sim/sim_panel.rb` に `GPIO` スタブ（`GPIO::IN` / `PULL_UP` / `read` / `high?` / `low?`）
- `lib/picorubykaigi01.rb` に `Buttons`
  - GPIO17〜22 を `:up :down :left :right :a :b` に対応（xlsx のピン割当どおり）
  - **負論理**（押下で L）。`pressed?(:a)`、`any?`、チャタリング除去
  - GPIO が連番なので一括読みできる形にしておく
- 画面: 6 個のボタン + **キーボード**（矢印キー / Z / X）
- 押している間 L、離すと H

### 4-2. tick ループ

ゲームも音楽も、時間が進まないと成立しない。
PicoRuby.wasm は `JS.global.setTimeout(ms) { }` を持つ（`callback_id` を返す）。

- `Board.every(ms) { }` のような形で再帰スケジュールする仕組みを 1 つ用意する
- Run のたびに前のループを止める（`clearTimeout`）。**止め忘れると二重に走る**

⚠️ ここは未検証。**最初に小さく試して、動かなければ設計を変える**。

### 4-3. 音声

- `sim/sim_audio.rb`: `WebAudio::Synth` を包み、`MIDIBASE::Router` に繋ぐ
- `lib/picorubykaigi01.rb` の `Speaker`
  - `play_mml("cdefg")` — MML を鳴らす
  - `tone(note, ms)` — 単音
  - `stop`
  - 実機では PSG、ブラウザでは WebAudio。**バックエンドを注入**
- midibase / midibase-mml の 10 ファイルを `index.html` の連結対象に追加
- **ノートログを画面に出す**。何がいつ鳴ったかが見えると作りやすく、
  かつ**ヘッドレスで機械的に検証できる**（音は聞けないので）

### 4-4. サンプル

| # | 内容 | 使う機能 |
|---|---|---|
| 1 | ボタンでドットを動かす | Buttons + LedMatrix |
| 2 | A で音が鳴る | Buttons + Speaker |
| 3 | MML でメロディ | Speaker |
| 4 | 音に合わせて光る | Speaker + LedMatrix |
| 5 | 簡単なゲーム | 全部 + tick |

## 5. 検証

### ヘッドレス `rake sim:test`（ブラウザ不要）

- `Buttons` の負論理・キーマップ・チャタリング除去
- **MML → MIDI イベント列**が期待どおり（実パーサが動くので中身を assert できる）
- `Speaker` がバックエンドに渡すイベント

### ブラウザ `rake sim:check`

- 画面のボタンを押す → パネルが変わる
- キーボード入力 → 同じ結果
- MML サンプルを Run → **ノートログに期待する音符列**が出る
- console エラーゼロ

音そのものは聞けない。**ノートログで代替する**ことを明記しておく。

## 6. リスク

| リスク | 退避策 |
|---|---|
| **tick ループが期待どおり動かない** | 最初に単体で試す。駄目なら「1 フレーム進める」ボタンによる手動ステップに落とす |
| midibase 10 ファイルの連結順 | `require "midibase"` しかないので、midibase → midibase-mml の順で足りるはず。駄目なら依存順に並べる |
| `WebAudio::Synth` が stock で動かない | `MIDIBASE::VoiceAllocator` はインスタンス生成時にしか要らないことは確認済み。それでも駄目なら自前の薄い WebAudio ラッパに落とす（音は出せる） |
| ブラウザの自動再生ポリシー | `synth.resume` はユーザ操作から呼ぶ必要がある。「音を有効にする」ボタンを置く |
| ボードレイヤ移設で LED が壊れる | `rake sim:test` と `rake sim:check` が既にあるので、移設直後に回す |

## 7. 進め方

1. ボードレイヤの器を作り `LedMatrix` を移す → **既存の検証が通ることを確認**
2. tick ループを単体で試す（ここが未知）
3. ボタン
4. 音声
5. サンプルとテスト
