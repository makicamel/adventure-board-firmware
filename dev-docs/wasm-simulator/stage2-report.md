# Stage 2 完了レポート — フォントと描画 API

計画: [stage2-plan.md](stage2-plan.md)

## 1. 結論

**完了。16×16 に漢字が出た。**

```
--- kanji ---   matrix.draw_text("宝")
    0123456789012345
  1 .......#........
  2 .......#........
  3 .##############.
  4 .#............#.
  5 .#............#.
  6 .#.##########.#.
  7 .......#........
  8 .......#........
  9 .......#........
 10 ...##########...
 11 .......#........
 12 .......#...#....
 13 .......#....#...
 14 .......#....#...
 15 .##############.
 16 ................
```

`docs/led_research_results.md` が 16×16 を選んだ理由に挙げた
「JIS 16×16 の漢字ビットマップフォントがそのまま表示できる」が、
**基板の前に実証できた**。

ヘッドレス 44/44、ブラウザ 14 サンプル・エラーゼロ。

## 2. emsdk — 追加インストール不要だった

`/home/kishima/fmrb/family-mruby` の Wasm 開発で使った **emsdk 6.0.6 が
`~/emsdk` に既にあった**。Docker イメージに 1〜2GB 足す必要はなかった。

**ホストの emsdk をコンテナにマウントする**方式。

- `~/emsdk/.emscripten` は `$CFGDIR` 相対なのでマウント先で解決できる
- node はバンドル済み（`node/24.19.0_64bit`）
- **ホストと同じパスにマウントする。** emscripten は SDK の場所でキャッシュを
  無効化するので、`/opt/emsdk` に置いたら `config changed, clearing cache` が出た

```console
rake sim:wasm     # EMSDK_DIR で場所を指定可（既定 ~/emsdk）
```

## 3. 成果物

```
build_config/picoruby-wasm.rb   PICOBOARD_WASM で囲った追加 gem（upstream の挙動は不変）
docker/compose.yml              wasm サービス（emsdk をマウント）
docker/Dockerfile               brotli を追加
tasks/sim.rake                  rake sim:wasm
sim/vendor/                     ビルドした wasm 3 点（git 管理外、2.7MB）
sim/index.html                  vendor があればそれを、無ければ CDN
lib/picorubykaigi01.rb          LedMatrix に描画 API
sim/examples/kanji.rb           漢字
sim/examples/scroll.rb          文字スクロール
sim/examples/shapes.rb          線と矩形
```

## 4. 設計

### 描画は 2 系統

`picoruby-vram` は 1bit なので、**明るさ付きの点と、図形・文字は別系統**にした。

```ruby
matrix.set(x, y, pwm)       # ドット単位・8bit の明るさ
matrix.draw_text("宝")       # VRAM へ（1bit）
matrix.blit(on: 0xC0)        # VRAM の 1bit を PWM に焼き付ける。明るさはここで決める
matrix.show
```

`blit` は 256 回の代入。**上位層で C 化する価値があるとすればここ**で、
それ以外の描画経路に per-pixel の処理は無い。Stage 1 の時点で予想した場所と一致した。

`include Shinonome::Drawable` は `begin/rescue NameError` で囲ってある。
フォント gem の無いビルドでも `LedMatrix` は読み込める。

### ローカル wasm はフォールバック付き

`sim/vendor/` があればそれを、無ければ CDN を読む。
**ビルドしていなくてもシミュレータは動く**（フォントだけ使えない）。
wasm バイナリ 2.7MB は git に入れない。

## 5. 詰まって解いた点

| # | 内容 |
|---|---|
| 1 | **`brotli` がイメージに無かった。** wasm 自体は最後まで通っていて、`brotli -f picoruby.wasm` だけが status 127 で落ちていた。apt に追加 |
| 2 | **compose の `${VAR:?}` はファイル全体の検証を壊す。** `EMSDK_DIR` を必須変数にしたら、`sim:check` を含む**すべての** compose コマンドが動かなくなった。既定値にして、実在チェックは rake 側に置いた |
| 3 | **ハーネスの静的サーバが `.wasm` の MIME を返していなかった。** ブラウザがストリーミングコンパイルを拒否して ArrayBuffer にフォールバックしていた（動くが遅い） |
| 4 | **HEAD プローブが `ERR_ABORTED` になる。** これから script として読む URL に HEAD を投げると中断扱いになる。GET に変更（数 KB で、script 読み込み時はキャッシュが効く） |
| 5 | npm の成果物は**全部 gitignore 済み**だった。ビルド後に `git checkout` で戻す必要は無かった |

## 6. 既知の制限

| 項目 | 内容 |
|---|---|
| フォントは 1bit | VRAM が MONO のみ。文字の階調は `blit(on:)` で全体を決めるだけ |
| `blit` のコスト | 256 回の代入。スクロールは 90ms 間隔で問題なかったが、実機で測り直す価値はある |
| スクロールの折り返し | 全角 16px の概算。半角混じりだと端数が出る |
| wasm のサイズ | 2.7MB。フォントデータを含む。stock との差は未計測 |
| 演奏テンポ | ブラウザでは譜面より 1〜2 割速い（Stage 1b から継続） |

## 7. 次

- 実機側へ戻る: `/lib/picorubykaigi01.rb` の配布方法
  （[../board-gems/README.md](../board-gems/README.md) §3-2）
- GROVE / ステータス LED
- 基板用 build_config と実機ブリングアップ（基板待ち）
