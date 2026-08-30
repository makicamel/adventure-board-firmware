# Stage 1c 完了レポート — UI を Funicular へ

計画: [stage1c-plan.md](stage1c-plan.md)

## 1. 結論

**完了。UI が全部 Ruby になった。** ヘッドレス 44/44、ブラウザ 11 サンプル・エラーゼロ。

**受け入れ条件だった「検証ハーネスを一行も変えずに通ること」を満たした。**
ハーネスは `#run` / `#notelog` / `[data-pin="20"]` といった DOM のセレクタで
操作しているので、これが通るということは**外から見た振る舞いが変わっていない**
ことの証拠になる。

## 2. 変わったもの

| | 前 | 後 |
|---|---|---|
| UI | `sim/sim_ui.rb`（手書きの DOM 操作、370 行） | `sim/sim_app.rb`（`Funicular::Component`、460 行） |
| HTML | 要素をすべて手で書いた 158 行 | `<div id="app">` と CSS と `renderPanel` だけ |
| 状態管理 | `className` を直接書き換え | `state` と `patch` |

追加ビルドは不要だった。`picoruby-funicular` は
`build_config/picoruby-wasm.rb` に入っているので stock パッケージに同梱されている。

## 3. 何を state に置き、何を ref にしたか

VDOM の差分は state が変わるたびに走るので、**速く変わるものは state に置かない**。

| | 置き場所 |
|---|---|
| ステータス文言と種別、GCC 値、音の有効/無効、押されているボタン | **state** |
| 16×16 の描画（canvas） | **ref** — 毎フレーム。256 個の要素を差分更新するのはコストが読めない |
| コード入力欄 | **ref** — state に入れると入力のたびに再描画されてカーソルが飛ぶ |
| ノートログ | **ref** — 150ms ごとに伸びる |

これは逃げではなくフレームワーク側の作法で、
`demo/www/webaudio.rb` も同じ理由で `canvas(ref: :scope)` を使っている。

## 4. 詰まって解いた点

### 4-1. `pre` はタグ DSL に無い

`0_tags.rb` の `HTML_TAGS` は `div span p a data h1-h6 ul ol li table... form input
textarea button select option label header footer nav section article aside
img video audio canvas br hr`。`pre` は入っていないので、
汎用の `tag("pre", ...)` を使う。

### 4-2. 子要素は戻り値ではなく副作用で集まる

`ViewContext#capture` は、ブロック内で作られた要素を `current_children` へ
push していく。戻り値が使われるのは **children が空のときだけ**。
ヘルパーメソッドの中でタグを呼べばそれで足りるので、配列を組んで返す必要はない。

### 4-3. クラスメソッドから呼ぶものは private にできない

実行ループはインスタンスより長生きするのでクラスメソッドに置いたが、
そこから `$app.draw` / `$app.report` を呼ぶ。
`private method 'report' called for SimApp` で落ちた。`public :draw, :report` を明示。

### 4-4. ★canvas は後からマウントされる

`renderPanel` の JS が読み込み時に `document.getElementById('panel')` を掴んでいたが、
**Funicular が canvas を作るのはその後**。null に `getContext` して例外になり、
`window.renderPanel` そのものが定義されないまま終わっていた。

しかもこの失敗は**静かだった**: Ruby 側から存在しない JS 関数を呼んでも
例外にならず、`Method not found or not a function: renderPanel` が
console に出るだけ。ハーネスが console を拾っていなければ気づけなかった。

→ canvas は**呼び出しのたびに遅延取得**して、見つかるまで何もしない形にした。

### 4-5. ハーネスが落ちるとコンソールを出せていなかった

ページが立ち上がらないとき `#status` の待ちでタイムアウトして終了し、
**原因が書かれている console 出力を出さずに死んでいた**。
読めるものは読み、最後に必ず console とエラーを出すよう直した。
この修正が無ければ 4-1 以降の原因究明ができなかった。

## 5. 得られたもの / 得られなかったもの

**得られた**: UI が Ruby。イベントの付け替えも `className` の書き換えも消えて、
`state` からの派生になった。PicoRubyKaigi 向けとして「全部 Ruby」が成立した。

**得られていない**: 機能は 1 つも増えていない。行数もほぼ同じ。
canvas・入力欄・ノートログは結局 ref 管理のままで、
そこは手書きの DOM 操作が残っている。

## 6. 次

- **Stage 2** — emsdk を入れて `picoruby-vram` / `picoruby-shinonome` を wasm に足し、
  フォント描画と VRAM の描画 API を通す
- あるいは実機側へ戻り、`/lib/picorubykaigi01.rb` の配布方法
  （[../board-gems/README.md](../board-gems/README.md) §3-2）を詰める
