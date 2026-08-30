# 実装計画 — 2ページ構成と実機転送

調査: [README.md](README.md)

## 0. まず実機で経路だけ確かめる（実装前）

**Pico 2 W と既存の `terminal.html` だけで確認できる。** 新しいものは何も要らない。
ここが通れば設計が確定し、通らなければ組み込む前に分かる。

### 手順

```console
# 1. ファームを焼く（BOOTSEL を押しながら挿して uf2 をコピー）
rake docker:r2p2:picoruby:pico2_w:prod
#    → dist/picoruby-pico2_w-prod/R2P2-*.uf2

# 2. デモサーバを起動（WASM_BUILD=dist で、こちらでビルドした dist を使う）
WASM_BUILD=dist rake wasm:server
```

ブラウザ（**Chrome か Edge**）で `http://localhost:8080/terminal.html` を開き、

1. **Connect** → ポート選択で **CDC0**（R2P2 は CDC を3本出す。0 がシェル）
2. ターミナルに R2P2 のプロンプトが出ることを確認
3. **File Editor** の欄でモードを **Plain** にする（Compile にすると `.mrb` になる）
4. エディタに短いコードを貼る。例:

   ```ruby
   puts "hello from the browser"
   3.times { |i| puts i }
   ```

5. パスを `/home/test.rb` にして **Upload**
6. ターミナルに戻って `/home/test.rb` と打つ

### 期待する結果

- Upload がエラーなく完了する
- `/home/test.rb` で `hello from the browser` と `0 1 2` が出る

### 確認できていること（コードから）

- ページは **STX (`\x02`) を送り、ACK (`\x06`) を待って** PicoModem に入る
  （`terminal.html` の `picomodem_enter_mode`）
- 実機側は `Shell#run_shell` の Ctrl-B が `\x06` を返して
  `PicoModem.session($stdin, $stdout)` に入る
- **`picoruby-picomodem` は我々のファームに入っている**
  （`picoruby-shell` が依存。pico2_w の `gem_init.c` で確認）
- シェルは `/` で始まる名前をファイルとして解決し、`Sandbox#load_file` で実行する
  （`Shell.find_executable` と `Job#exec`）。**`ruby` コマンドは要らない**

### 通らなかったら見るところ

| 症状 | 見るところ |
|---|---|
| ポートが出ない | Chrome / Edge か。`localhost` か HTTPS か |
| プロンプトが出ない | CDC0 を選んだか。ボーレート 115200 |
| Upload が固まる | ACK が返っているか。ターミナルに `^B` が出ているか |
| 実行されない | パスがタイプミスしていないか。`ls /home` で確認 |

## 1. 2ページ構成

| | ページ | 内容 | 実機 |
|---|---|---|---|
| **A** | シミュレータ | 16×16 パネル + ボタン + エディタ + **Run が2つ** | 任意 |
| **B** | 実機コンソール | xterm.js のフルシェル。IRB・ファイル操作・`/lib` の配置 | 必須 |

**A に実機への転送と実行を持たせる**のが要点。ページを移るとコードを持って行けず、
「書く → ブラウザで試す → 実機で試す」の流れが切れる。
同じエディタに Run が2つ並んでいれば、**「同じコードが両方で動く」が操作で示せる**。

B はフルシェルが要るとき用に残す。

### A の [実機で実行] がやること

1. **接続**（未接続なら）— WebSerial のポート選択。CDC0 を選ぶよう案内する
2. STX を送り ACK を待つ → PicoModem セッション
3. エディタの内容を **Plain** で `/home/app.rb` へアップロード
4. セッションを抜け、シェルへ `/home/app.rb\n` を送る
5. 実機の stdout を A の小さなログ欄に出す（ノートログと同じ扱いで、既定は非表示）

### 共有するもの

```
lib/picorubykaigi01.rb   ボードレイヤ（A はブラウザで実行、B の転送先で動く）
sim/examples/*.rb        ★同じサンプルを両ページで選べる
Funicular コンポーネント  エディタ、サンプル選択、ステータス
CSS
```

サンプルが共有できることが本体。シミュレータ専用構文を禁止した結果、
A で書いたものをそのまま実機へ送れる。

## 2. 置き場所

`sim/` は2ページになると名前が狭い。

```
web/simulator.html    ← 現 sim/index.html
web/device.html       ← 新規（B）
web/app/*.rb          共有コンポーネントとシミュレータ
web/examples/*.rb     サンプル
web/vendor/           ローカルの PicoRuby.wasm（git 管理外）
```

`rake sim:*` と `tools/browser-check/check.cjs` のパスも変わる。
**移すなら 2ページ化と同時に一度で**やる方が混乱が少ない。

## 3. 検証

| | 手段 |
|---|---|
| A のブラウザ実行 | `rake sim:check`（現行どおり全項目を機械判定） |
| **A の実機実行** | **自動化できない。** Playwright は WebSerial を扱えない |
| B | 同上。手で確かめる |

**同じページの中で検証手段が2つに割れる**ことは受け入れる。
せめて「接続していないときに [実機で実行] が正しく無効化されるか」までは
ハーネスで見られる。

## 4. 手順

1. **§0 の経路確認**（実機が要る。ここだけ先にやりたい）
2. `web/` への移動と2ページ化。A はまず現状のまま移すだけ。`rake sim:check` が
   パス変更後も全項目通ることを確認する
3. A に接続と [実機で実行] を足す
4. B（xterm.js のフルシェル）。`terminal.html` を Funicular へ書き直すか、
   `ref` で xterm.js を掴む形にする

3 と 4 は独立しているので、どちらからでもよい。

## 5. リスク

| リスク | 退避策 |
|---|---|
| §0 が通らない | 組み込む前に分かる。原因次第（PicoModem 側か、シェルの実行側か）で判断 |
| `web/` への移動で既存の検証が壊れる | 移動だけを1コミットにして `rake sim:check` を通してから中身に触る |
| A に実機機能を足して A 自体が壊れる | ブラウザ実行側は `rake sim:check` が守る。実機側は無効化状態の見た目まではハーネスで見る |
| xterm.js を Funicular に載せるのが重い | B は当面 `terminal.html` をそのまま置く（統合しない）でもよい |
