# Stage 1c 実装計画 — UI を Funicular へ

親計画: [README.md](README.md) / 前段: [stage1b-report.md](stage1b-report.md)

## 1. 目的

シミュレータの UI を、手書きの DOM 操作から **Funicular**（PicoRuby.wasm の
VDOM ベース SPA フレームワーク）へ移す。**UI も Ruby で書けるようにする。**

機能は増えない。得られるのは保守性と、「PicoRuby のイベント用に作ったものが
全部 Ruby で書かれている」という一貫性。

## 2. 使えることの確認

`build_config/picoruby-wasm.rb` に `conf.gem core: 'picoruby-funicular'` があるので
**stock の `@picoruby/wasm-wasi` に入っている。追加ビルドは不要。**

読んで確認した API:

| | |
|---|---|
| 起動 | `Funicular.start(SimApp, container: 'app')` |
| 状態 | `state[:key]` を読み、`patch(key: value)` で更新して再描画 |
| タグ | `div(class: "x") { }`、`button(onclick: :run) { "Run" }` のバックワード DSL |
| イベント | 属性名が `on` で始まればすべてイベント（`vdom.rb`）。**`onmousedown` も `onkeydown` も使える** |
| ハンドラ | Symbol なら `send(name, event)` で呼ばれる。**イベントを受け取れる** |
| DOM 直接 | `canvas(ref: :panel)` として `refs[:panel]` で掴む |
| ライフサイクル | `component_will_mount` / `component_mounted` / `component_will_update` / `component_updated` |

`demo/www/webaudio.rb` が実例（`canvas(ref: :scope)` を `refs[:scope]` で描いている）。

## 3. 設計

### 何を state に置き、何を ref にするか

VDOM の差分は state が変わるたびに走るので、**速く変わるものは state に置かない**。

| | 置き場所 | 理由 |
|---|---|---|
| ステータス文言と種別 | **state** | 見た目が変わる。頻度は低い |
| GCC の値 | **state** | 同上 |
| 音が有効か | **state** | ボタンの表示が変わる |
| 押されているボタン | **state** | ハイライトの class が変わる |
| **16×16 の描画** | **ref (canvas)** | 毎フレーム。256 個の div を差分更新するのはコストが読めない |
| **コード入力欄の中身** | **ref (textarea)** | state に入れると入力のたびに再描画され、カーソルが飛ぶ |
| **ノートログ** | **ref (pre)** | 150ms ごとに伸びる。`webaudio.rb` も同じ理由で ref を使っている |

つまり **canvas とテキスト 2 か所は ref のまま**で、それ以外が Funicular に乗る。
これは逃げではなく、フレームワーク側の作法（デモがそうしている）。

### ファイル

```
sim/sim_app.rb    Funicular::Component（sim_ui.rb を置き換える）
sim/index.html    <div id="app"> と CSS と renderPanel だけに縮む
```

`renderPanel` の JS は残す。canvas への描画は Funicular の管轄外。

## 4. 注意点

- **HTML タグ名はコンポーネントのメソッド名に使えない**（`0_tags.rb` の
  `RESERVED_DSL`、`validate_dsl_conflicts!` が検出する）。
  `code` も `audio` も `select` もタグ名なので、メソッド名には使わない
- **`while` の中でハンドラの lambda を作らない**（Stage 1b で踏んだ罠）。
  Symbol ハンドラ + `event.target` の `data-pin` を読む形にすれば、そもそも作らない
- 再描画で canvas が作り直されると絵が消える。`component_updated` で描き直す

## 5. 検証

**既存の検証がそのまま通ることが受け入れ条件。** 機能を増やさないので:

- `rake sim:test` — 44/44（UI に触らないので影響なし）
- `rake sim:check` — 11 サンプル全部、ボタン操作、ノートログ、エラーゼロ

ハーネスは DOM のセレクタ（`#run`、`[data-pin="20"]`、`#notelog`、`#examples`）で
操作しているので、**同じ id と属性を維持すれば書き換え不要**。
これが移行できたことの一番の証拠になる。

## 6. リスク

| リスク | 退避策 |
|---|---|
| Funicular が stock パッケージで期待どおり動かない | 最初に最小のコンポーネントを 1 つ描いて確かめる |
| 再描画で canvas やテキストエリアの中身が飛ぶ | ref 管理にしてある。`component_updated` で描き直す |
| ハンドラのイベント引数が期待と違う | `bind_events` は `send(name, event)` と読めた。駄目なら lambda に切り替える |
| 移行で既存機能が壊れる | `sim:check` が 11 サンプルを回すので、壊れれば出る |
