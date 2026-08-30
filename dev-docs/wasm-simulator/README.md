# ブラウザ LED シミュレータ（PicoRuby.wasm）

ブラウザで Ruby を走らせ、16×16 マトリクスの光り方を目で見る仕組み。
実機が無い期間の検証手段であり、そのままワークショップ教材にもなる。

## 1. なぜこれが効くのか

計画に元々あった「Console バックエンド」（シリアルに ASCII アートを出す）より
上位互換になる。**Console バックエンドはドライバを迂回するが、
シミュレータは仮想 IS31FL3729 を置いて実際のレジスタ書き込みをデコードするので、
ドライバのコードが一切改変なしで走る。**

そして何より、**実機なしでは他に確かめようのない唯一の高リスク項目**を潰せる:

- `netlist.ipc` から導出した座標マッピング（[../led-matrix-gem/hardware.md](../led-matrix-gem/hardware.md) §4）
- とくに **U11 側の列反転 `cs = 17 - c`**
- 行が 8/9 でチップをまたぐ境界
- 上下・左右の向き

漢字がチップ境界をまたいで正しく出るのを**目で見る**のが、この仕組みの本当の対価。
配線から読んだ対応表が合っているかは、これでしか確認できない。

副次的な効果:

- 基板が届く前にサンプルプログラムを書き切って、見た目まで詰められる
- ワークショップ参加者が基板を手にする前に、あるいは基板なしでも試せる
- PicoRubyKaigi の題材として、PicoRuby.wasm 自体の宣伝にもなる

## 2. 分かっていること

`mrbgems/picoruby-wasm` を読んで確認した事実。

- 公開 npm パッケージ **`@picoruby/wasm-wasi`** を jsDelivr の CDN から読むだけで、
  ブラウザで Ruby が動く。**emsdk もビルドも要らない**

  ```html
  <script src="https://cdn.jsdelivr.net/npm/@picoruby/wasm-wasi@latest/dist/init.iife.js"></script>
  <script type="text/ruby" src="app.rb"></script>
  ```

- `demo/www/` に既存のデモが多数ある。**`terminal.html`（879行）は
  UI ロジックがまるごと `<script type="text/ruby">` で書かれている**。
  xterm.js を Ruby から叩いており、DOM 操作の手本になる
- したがって**シミュレータ側のコードも Ruby で書ける**。PicoRuby のイベント向けとして筋がいい

### 使える gem / 使えない gem

`build_config/picoruby-wasm.rb` が入れているのは
`mruby-posix` / `stdlib` gembox と `picoruby-wasm` / `indexeddb` / `funicular` /
`markdown` / `drb` / `sqlite3`。つまり:

| | stock パッケージで動くか |
|---|---|
| `is31fl3729.rb`（**純 Ruby**） | ✅ ソースをそのまま読ませれば動く |
| `I2C`（仮想チップへの橋渡し） | ✅ Ruby で自前定義。実 gem が無いので名前も衝突しない |
| `/lib/picorubykaigi01.rb` の非フォント部分 | ✅ |
| **`picoruby-vram`**（C 拡張） | ❌ stock には入っていない |
| **`picoruby-shinonome` / `bdffont`**（C 拡張） | ❌ 同上 |

**表示層が VRAM と Shinonome に依存する以上、stock パッケージだけでは
フォント描画まではいけない。** ここが段階を分ける理由。

## 3. 二段階でやる

### Stage 1 — 機構ゼロで今すぐ（推奨: 先にやる）

CDN の stock パッケージ + `mrblib/is31fl3729.rb` のソース + 仮想チップ。

```
ブラウザ
 ├ <script type="text/ruby"> で読む:
 │   ・is31fl3729.rb（リポジトリのファイルをそのまま）
 │   ・class I2C  … write(addr, *outputs) を仮想チップへ渡すだけ
 │   ・VirtualIS31FL3729 … レジスタをデコードして 128 バイトの PWM を保持
 │   ・Panel … 2チップ分を 16×16 に合成して DOM/canvas へ描く
 │            （U11 の列反転もここで実装 = 実機と同じ変換を検証できる）
 └ 入力: 右側にテキストエリア、書いた Ruby をその場で実行
```

これで確認できること:

- ドット単位 API と 2 チップ合成、**座標マッピングの正しさ**
- GCC / Scaling を反映した明るさ（8bit PWM をそのまま輝度に落とせる）
- 初期化を忘れると光らないこと（POR で GCC / SL が 0）まで含めて再現できる

**やらないこと**: フォント、VRAM の描画 API。Stage 2 に回す。

### Stage 2 — 表示層まで通す

`build_config/picoruby-wasm.rb` に `picoruby-vram` / `picoruby-shinonome` /
`picoruby-bdffont` / `picoruby-is31fl3729` を足し、自前で wasm をビルドする。

- **emsdk が必要**。Docker イメージに追加することになる（+1〜2GB）
- `rake wasm:build_prod` / `rake wasm:server`（`tasks/picoruby/wasm.rake`）
- ⚠️ `AGENTS.md` の注意: **wasm のビルド・テストはサンドボックス外で実行すること**
  （emscripten が SDK ディレクトリにキャッシュとロックを書く）。
  また **`build/host` を共有するので他のビルドと同時に走らせない**

ここまで来ると、`/lib/picorubykaigi01.rb` とサンプルが**丸ごとブラウザで動く**。
漢字スクロールもライフゲームも、実機と同じコードで見た目を詰められる。

### 既存 Web コンソールとの関係

`demo/www/terminal.html` は R2P2 のターミナル UI で、DFU のファイル転送欄も持つ。
Stage 2 まで行けば、**「左に IRB、右に 16×16 パネル」**という構成が自然に組める。
`terminal.html` の作りをそのまま流用できる。

## 4. 計画上の位置づけ

[../led-matrix-gem/plan.md](../led-matrix-gem/plan.md) の Phase 2 にあった
「Console バックエンド」を、これで置き換える。

| | 変更前 | 変更後 |
|---|---|---|
| Phase 2 の検証手段 | Console バックエンド（ASCII アート） | **ブラウザシミュレータ** |
| 検証できる範囲 | 表示層の見た目だけ | **ドライバのレジスタ出力まで**（実コードが走る） |
| 座標マッピングの検証 | できない | **できる** ← これが本命 |

Console バックエンドを完全に捨てるかは要判断。シリアルだけで完結する利点はあるので、
「実機の R2P2 上で手早く確認する手段」として残しておいてもよい。

## 4-1. 実施状況

| 段階 | 内容 | 結果 |
|---|---|---|
| [Stage 1](stage1-report.md) | LED。実ドライバ + 仮想チップ + canvas | ✅ 座標マッピングを目視確認 |
| [Stage 1b](stage1b-report.md) | ボタンと音声。ボードレイヤを本物として作成 | ✅ MML パイプラインが実物のまま動作 |
| [Stage 1c](stage1c-report.md) | UI を Funicular へ | ✅ UI が全部 Ruby に |
| Stage 2 | フォント（shinonome）と VRAM | ⬜ emsdk が要る |

## 5. 「先に作るか」への答え

**Stage 1 は先にやる価値がある。** ドライバ（Phase 1）は既に 20 テスト / 52
アサーションで固まっているが、**2 チップ合成と座標マッピングは一度も目視されていない**。
そこを先に潰しておくと、表示層を書くときの土台が確かになる。

一方 Stage 2 は emsdk の導入という重い一歩を含むので、
表示層を書き始めて「フォントの見た目を確認したい」となった時点で判断するのがよい。
