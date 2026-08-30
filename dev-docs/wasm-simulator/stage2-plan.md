# Stage 2 実装計画 — フォントと描画 API

親計画: [README.md](README.md) / 前段: [stage1c-report.md](stage1c-report.md)

## 1. 目的

**16×16 に漢字を出す。** 16×16 を選んだ理由そのもの
（`docs/led_research_results.md`: 「JIS 16×16 の漢字ビットマップフォントが
そのまま表示できる。12×12 では不可能」）を、実機の前に確かめる。

併せて `picoruby-vram` の描画 API（線・矩形・ビットマップ）も通す。

## 2. なぜ自前ビルドが要るか

stock の `@picoruby/wasm-wasi` は `build_config/picoruby-wasm.rb` で作られていて、
そこに **`picoruby-vram` / `picoruby-shinonome` / `picoruby-bdffont` が入っていない**。
どれも C 拡張なので、Stage 1 でやったような「純 Ruby のソースを fetch して連結」は使えない。

## 3. emsdk — 追加インストール不要だった

`~/emsdk` に **6.0.6 が既にインストール済み**だった
（`/home/kishima/fmrb/family-mruby` の Wasm 開発で使ったもの）。
Docker イメージに 1〜2GB 足す必要はない。

**ホストの emsdk をコンテナにマウントする**方式にした。確認済みの点:

- `~/emsdk/.emscripten` は `$CFGDIR` 相対で書かれているので、マウント先でも解決できる
- node はバンドルされている（`~/emsdk/node/24.19.0_64bit`）
- **ホストと同じパスにマウントする。** emscripten は SDK の場所でキャッシュを
  無効化するので、違うパスに置くと切り替えのたびにキャッシュが飛ぶ
  （実際 `/opt/emsdk` に置いたら `config changed, clearing cache` が出た）

## 4. 設計

### ビルド

`build_config/picoruby-wasm.rb` に `PICOBOARD_WASM` で囲った追加 gem を置く。
upstream のファイルだが、**環境変数が無ければ従来どおり**なので
`rake wasm:build_prod` の結果は変わらない。

```console
rake sim:wasm
```

- コンテナ内で `PICOBOARD_WASM=1 CONFIG=picoruby-wasm rake`
- 成果物 3 つ（`init.iife.js` / `picoruby.js` / `picoruby.wasm`）を `sim/vendor/` へコピー
- ビルドは upstream の `npm/picoruby/dist` を上書きするので、**最後に git で戻す**

### ページ側

`sim/vendor/` があればそれを、無ければ CDN を読む。
**ビルドしていなくてもシミュレータは動く**（フォントだけ使えない）。
`sim/vendor/` は git 管理外（wasm バイナリは数 MB）。

### ボードレイヤ

`LedMatrix` に VRAM を持たせ、`VRAM::Delegatable` と `Shinonome::Drawable` を
include する。実機でも同じコードが動く（どちらの gem も
`build_config/r2p2-picoruby-pico2.rb` に既にある）。

```ruby
matrix.draw_shinonome("16", 0, 0, "宝")
matrix.draw_line(0, 0, 15, 15)
matrix.show
```

`picoruby-vram` は現状 `PIXEL_FORMAT_MONO` のみなので、
**VRAM 経由の描画は点灯/消灯だけ**。階調は今までどおり `set(x, y, pwm)` を使う。
この二本立てをそのまま API として出す。

## 5. 検証

- `rake sim:test` — VRAM/Shinonome は C 拡張で `bin/picoruby`（ホストビルド）には
  入っているので、**ヘッドレスでもフォントのビットマップを検証できる見込み**。
  駄目ならブラウザ側だけで見る
- `rake sim:check` — 漢字サンプルを追加し、**canvas から読み戻した 16×16 が
  期待する字形になっているか**を確認する。ここが本命

## 6. リスク

| リスク | 退避策 |
|---|---|
| C 拡張が emcc で通らない | エラーを見て個別対応。最悪 shinonome だけ諦めて vram のみ |
| `picoruby-shinonome` のフォントデータで wasm が大きくなりすぎる | サイズを測る。大きければ 16×16 のゴシックだけに絞る |
| ビルドが upstream の npm ディレクトリを汚す | コピー後に `git checkout` で戻す（タスクに実装済み） |
| emsdk のキャッシュがホストとコンテナで競合 | 同じパスにマウントして回避済み |
| `VRAM::Delegatable` が期待どおり include できない | `picoruby-ssd1306` が実例なので、そこに倣う |
