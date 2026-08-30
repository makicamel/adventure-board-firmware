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
matrix.set(4, 5, 0x40)  # 3 番目の引数は PWM (0..255)
matrix.show             # これを呼ぶまでチップには届かない
```

**書き方は実機とまったく同じ。** シミュレータ専用の構文は無い。
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
`matrix.panel.i2c` は仮想バス。

## 構成

| ファイル | 役割 | JS 依存 |
|---|---|---|
| `sim_panel.rb` | `I2C` / `VirtualIS31FL3729` / `Panel` / `LedMatrix` | **なし** |
| `sim_ui.rb` | canvas 描画、エディタ、ボタン | あり |
| `index.html` | ページと描画関数 | — |
| `test/panel_test.rb` | ヘッドレス検証 | **なし** |

面白い部分（レジスタのデコードと 2 チップの座標合成）はすべて `sim_panel.rb` に
あり、JS に依存しない。だから**ブラウザ無しで検証できる**:

```console
rake sim:test
```

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
