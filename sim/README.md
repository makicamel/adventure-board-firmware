# LED マトリクス シミュレータ

ブラウザで **実機と同じ `IS31FL3729` ドライバ**を動かし、16×16 の光り方を目で見る。
基板が無い間の検証手段であり、そのまま教材にもなる。

## 使い方

```console
rake sim:server
# → http://localhost:8080/sim/ を開く
```

リポジトリのルートをサーバのルートにしている。
ページが `mrbgems/picoruby-is31fl3729/mrblib/is31fl3729.rb` を
**コピーではなく実ファイルとして**読むため。

右のテキストエリアに Ruby を書いて Run。左のパネルに結果が出る。

```ruby
matrix.clear
matrix.set(3, 5)        # x, y は 1..16
matrix.set(4, 5, 0x40)  # 3 番目の引数は明るさ (0..255)。見た目に比例するよう補正される
matrix.show             # これを呼ぶまでチップには届かない
```

**書き方は実機とまったく同じ。** シミュレータ専用の構文は無い。
サンプルの先頭にある `require 'picorubykaigi01'` は実機で必要なもので、
ブラウザでは（ソースが連結済みなので）何もしない。
繰り返しは `while true` + `sleep_ms` で書く。ブラウザではこのコードが
専用のタスクで走り、`sleep_ms` のあいだ画面に制御が戻るので固まらない。

```ruby
while true
  matrix.clear
  matrix.set(x, y)
  matrix.show
  sleep_ms 60
end
```

canvas は 50ms ごとに仮想チップの中身を映しているので、
「画面を更新しろ」と書く必要はない（実機のパネルが常時スキャンされているのと同じ）。

`matrix.top` / `matrix.bottom` で `IS31FL3729` を直接触れる。
`board.i2c` は LED ドライバのバス（ここでは仮想、実機では I2C0）。

**シミュレータ専用の構文はありません。** `board` / `matrix` / `buttons` /
`speaker` はすべて `lib/picorubykaigi01.rb` — 実機にも載るボードレイヤ — が
定義しています。ここで書いたサンプルはそのまま基板で動きます。
違うのは起動時にペリフェラルを組む部分だけで、それはサンプルの外にあります。

## 実機で実行

同じエディタのコードを、USB でつないだ基板に送って動かせる（Chrome / Edge のみ）。

1. 基板の USB シリアルを **Windows 側に置く**。WSL に渡している（`usbipd attach`）と、
   ブラウザのポート一覧に出ない。`usbipd detach --busid <BUSID>` で戻す
2. **[実機に接続]** → ポート選択で R2P2 の COM ポートを選ぶ。3 本出るので、
   プロンプト（`$>`）が「実機の出力」欄に出るもの（CDC0）が正解
3. **[実機で実行]** — 次を順に行う:
   1. Ctrl-C で実行中のプログラムを止め、プロンプトを待つ
   2. Ctrl-B でシェルのファイル転送（PicoModem）に入り、エディタの内容を
      `/home/app.rb` として送る。512 バイトごとに受信確認、最後に CRC32 を照合
   3. シェルに `/home/app.rb` を送って実行する

実機モードではパネルとボタンは使わない。LED は基板で光り、ボタンも基板のものを押す。
この経路はヘッドレスのブラウザでは USB を扱えないので、`rake sim:check` では確かめられない。

実行のたびに `/home/app.rb` を書き換える。**R2P2 は起動時にこのファイルを自動実行する**ので、
最後に流したスクリプトが次の起動でも走る（終わらないスクリプトだとシェルが出ない。
起動ログの `Press 's'` で `s` を送れば飛ばせる）。

「何度も実行していると実機が応答しなくなる」件（2026-09-14）は、PSG が core1 で動いているあいだに
フラッシュへ書くと core1 が固まるのが原因だった。2026-09-21 に修正
（[../dev-docs/upstream-issues.md](../dev-docs/upstream-issues.md) の 4）。
音を使わないスクリプトでも起きるなら別の原因なので、記録すること。

## 構成

| ファイル | 役割 | JS 依存 |
|---|---|---|
| `sim_panel.rb` | `I2C` / `VirtualIS31FL3729` / `Panel` / `LedMatrix` | **なし** |
| `sim_device.rb` | 実機との USB 接続と転送（`DeviceLink`）。サンプルからは呼ばない | あり |
| `sim_ui.rb` | canvas 描画、エディタ、ボタン | あり |
| `index.html` | ページと描画関数 | — |
| `test/panel_test.rb` | ヘッドレス検証 | **なし** |

面白い部分（レジスタのデコードと 2 チップの座標合成）はすべて `sim_panel.rb` に
あり、JS に依存しない。だから**ブラウザ無しで検証できる**:

```console
rake sim:test
```

## コードの色付け

コードの欄は構文で色が付く。解析は自前の字句解析ではなく、**PicoRuby のコンパイラが持っている Prism**
（Ruby の構文解析器）に任せている。`mrbgems/picoruby-syntax-highlight` の `SyntaxHighlight.tokenize(source)` が、
ソースの 1 バイトごとに 0〜8 の分類（キーワード・文字列・コメント・数値・シンボル・定数・`@` `$` の変数・メソッド名）を返す。
構文エラーの途中でも表は返るので、打っている最中も色が付く。

- 描画は「テキストエリアの下に、同じ文字を色付きで並べた `<pre>` を敷き、テキストエリアの文字を透明にする」方式。
  入力・選択・IME はテキストエリアのまま。2 枚の行の位置がずれないように、**行は折り返さない**
- Ruby 側（`CodeColors`、`sim_app.rb`）が分類の切れ目ごとに `<span class="kN">` を作り、`setCodeColors`（`index.html`）に渡す。
  ハートビートで欄の文字列を見て、**前に色を付けた文字列と違うときだけ**解析する（打鍵・貼り付け・サンプルの読み込みを区別しなくて済む）
- 色は `index.html` の `.k1`〜`.k8`。分類 8（メソッド名）は演算子や `[` `]` にも付くので控えめな色にしてある
- **`rake sim:wasm` で作った wasm が要る。** stock のパッケージ（CDN）には `SyntaxHighlight` が無く、そのときは色なしの今までどおりの欄になる
- `rake sim:check` は各サンプルで「色が付いているか・下の文字と欄の文字が一致するか・分類ごとの個数」を 1 行で報告する。
  見た目は `tools/browser-check/editor-shot.cjs`（欄をスクロールした絵を `tmp/browser-check/editor-colours.png` に出し、2 枚の位置と大きさを数字で出す）

## ブラウザでの検証

ページそのものはヘッドレス Chromium で確認できる。

```console
rake sim:check              # 全サンプルを実行して結果を報告
rake sim:check[l_shape]     # 1 つだけ
```

canvas のピクセルを読み戻して 16×16 のテキストに落とすので、目視ではなく
機械的に確認できる。console 出力とページエラーも報告し、
スクリーンショットは `tmp/browser-check/` に残る。
ファーム用とは別のイメージ（`docker/browser.Dockerfile`）を使う。

## 何を再現しているか

仮想チップは、ドライバが実際に書くレジスタをデコードする。

- アドレス自動インクリメント（ドライバの一括転送が前提にしている）
- PWM レジスタ 0x01〜（`(sw-1)*0x10 + cs`）
- `SSD` ビット（0 なら全消灯）
- `GCC`(0xA1) と Scaling(0x90〜0x9F) — **電源投入時は両方 0 なので光らない**
- Reset (0xCF ← 0xAE) で全レジスタが POR に戻る

輝度は `pwm/255 × gcc/64 × scaling/255`。実機の見え方の近似で、
光学的な正確さは狙っていない。

## 座標

上半分（y = 1..8）が U10 (0x34)、下半分（y = 9..16）が U11 (0x35)。
**U11 は列が左右反転して配線されている**ので、`cs = 17 - x` になる。
根拠は `dev-docs/led-matrix-gem/hardware.md` §4（r1 の netlist から導出）。

上下・左右のどちら向きが物理的な「上」「左」かは、実機で 1 ドット点灯するまで未確定。

## やっていないこと

フォント描画（`picoruby-shinonome`）と VRAM の描画 API。
どちらも C 拡張で、stock の `@picoruby/wasm-wasi` には入っていない。
`dev-docs/wasm-simulator/README.md` の Stage 2 で、
emsdk を入れて自前ビルドすれば通せる。
