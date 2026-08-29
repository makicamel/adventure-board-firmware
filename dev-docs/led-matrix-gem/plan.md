# LED マトリクス Gem 実装計画

対象: `picoruby-is31fl3729`（IS31FL3729 チップドライバ）と、その上の表示層。
ハード仕様は [hardware.md](hardware.md) を参照。

## 0. 前提と制約

- **基板はまだ製造中。IS31FL3729 の実チップは手元に無い。**
  したがって「実チップが無くても進む道」を設計の軸に置く。
- 開発機は Raspberry Pi Pico 2 W（`rake docker:r2p2:picoruby:pico2_w:prod` でビルド済み）。
- PicoRuby の gem 慣習に従う（`picoruby-ssd1306` / `picoruby-aht25` が手本）。
- `AGENTS.md` のライブラリ実装規約に従う:
  - `each` / `times` / `map` などブロック反復は避け、`while` + 明示的な整数インデックス
  - ivar を3回以上参照するならローカル変数にメモ化

## 1. 設計方針

### 1-1. 2層 + バックエンド差し替え

```
    アプリ / サンプルプログラム
              │
    ┌─────────▼──────────┐
    │ LedMatrix (16×16)  │  VRAM::Delegatable, Shinonome::Drawable
    │  表示層・座標系     │  draw_line / draw_rect / draw_shinonome ...
    └─────────┬──────────┘
              │ backend
    ┌─────────┴───────────────────────┐
    │                                 │
┌───▼────────────────┐   ┌────────────▼─────────┐
│ Backend::Console   │   │ Backend::IS31FL3729  │
│ シリアルへASCII    │   │ 2チップ合成 + I2C    │
│ **実機不要**       │   │ 実基板用             │
└────────────────────┘   └──────────┬───────────┘
                                    │
                         ┌──────────▼───────────┐
                         │ IS31FL3729 (16×8)    │ レジスタ層・汎用
                         └──────────────────────┘
```

この分割の狙い:

- **`IS31FL3729` は基板非依存の汎用チップドライバ**にする。16×8 単体で完結し、
  そのまま upstream picoruby に提案できる粒度にしておく。
- **`Backend::Console` があると、実チップが無い今でも Pico 2 W 実機で
  上位層とサンプルプログラムが動く。** シリアルコンソールに ASCII アートで
  16×16 を描くだけだが、フォント描画・アニメーション・ゲームロジックは
  これで完成まで持っていける。基板が来たらバックエンドを差し替えるだけ。
- レジスタ層のロジックは I2C をモックすればホストで完全に単体テストできる。

### 1-2. 階調をどう扱うか

IS31FL3729 はドットごとに 8bit PWM を持つが、`picoruby-vram` は現状
`PIXEL_FORMAT_MONO`（1bit）のみ実装されている。

そこで段階を分ける:

- **第1段（MONO）**: VRAM の 1bit バッファで点灯/消灯。明るさは GCC による全体制御。
  文字・図形・アニメーションはこれで十分。
- **第2段（GRAY8）**: `IS31FL3729` 側に 128 バイトの PWM バッファを持たせ、
  `set_dot(sw, cs, pwm)` で直接叩ける API を用意しておく。
  フェード・輝度グラデーションはこちらを使う。
  VRAM 本体への GRAY8 追加は upstream 側の TODO なので、当面は手を出さない。

## 2. フェーズ

### Phase 1 — レジスタ層（実機不要 / 最初の成果物）

**成果物**: `mrbgems/picoruby-is31fl3729/`

```
mrbgem.rake              spec.add_dependency 'picoruby-i2c'
mrblib/is31fl3729.rb     チップドライバ本体
sig/is31fl3729.rbs       型定義（Steepfile の対象に入る）
test/is31fl3729_test.rb  Picotest
test/mock/i2c.rb         書き込みを記録するフェイク I2C
README.md
example/
```

**API 案**:

```ruby
led = IS31FL3729.new(i2c: i2c, address: 0x34)   # reset せず、明示的に init
led.reset                                        # 0xCF <- 0xAE
led.configure(sws: 8, lgc: 1)                    # 0xA0: SWS=0b0001, SSD=1
led.global_current = 0x20                        # 0xA1 (0..0x40)
led.scaling_all = 0xFF                           # 0x90..0x9F 一括
led.set_dot(sw, cs, pwm)                         # ローカルバッファのみ更新
led.write_frame(bytes)                           # 0x01 から 128 バイト一括転送
led.flush                                        # 変更分だけ転送
led.shutdown / led.resume                        # SSD ビット
```

SDB は 2 チップ共通の 1 本なので、チップ層ではなく合成層（Phase 2）で持つ。
hardware.md §3-1 の通り **H にしてから 200µs 待ってから最初の I2C**、
停止時は **I2C を止めてから 200µs 空けて L**。この待ちを守らないと
初期化が黙って失敗するので、待ちはドライバ内部に閉じ込めて呼び出し側に任せない。
SDB の立ち上がりは I2C バスのリセットにも使えるため、
バスハングからの復旧 API も同じ場所に置く。

**確認すべき点**（テストで固定する）:

- PWM アドレス式 `(sw-1) * 0x10 + cs` が 0x01〜0x80 に写ること、
  とくに `(sw, 16)` が `sw * 0x10` になること
- POR 後は GCC も Scaling も 0 なので、初期化を忘れると光らないこと
- 128 バイト一括転送が 1 トランザクションになること（アドレス自動インクリメント）
- 論理座標 (列, 行) → (chip, SW, CS) の変換、とくに **U11 側の列反転 `cs = 17 - c`**
  （hardware.md §4-3）

**検証**:

```console
rake 'test:gems:picoruby[picoruby-is31fl3729]'
```

`picoruby-i2c` は `ports/` を持つプラットフォーム依存 gem なので、
テストガイドの Strategy 2（動的 require + モック）が適用される。
`test/mock/i2c.rb` を置けば実機もクロスビルドも不要で、ホストで即回る。

### Phase 2 — 表示層と Console バックエンド（Pico 2 W 実機で動く）

**成果物**: `mrbgems/picoruby-led-matrix/`（仮称）

- `LedMatrix.new(backend:, w: 16, h: 16)`
- `VRAM::Delegatable` を include → `set_pixel` / `draw_line` / `draw_rect` / `draw_bitmap`
- `Shinonome::Drawable` を include → **16×16 の漢字がそのまま出る**
  （`picoruby-shinonome` の `min16` / `go16`。16×16 マトリクスを選んだ理由そのもの）
- `Backend::Console#show(vram)` … シリアルに ASCII アートで出力
- `Backend::IS31FL3729#show(vram)` … 上下半分に切って 2 チップへ転送。
  SDB ピン（GPIO14）の制御もここ

この段階で Pico 2 W 実機のシェルから

```ruby
m = LedMatrix.new(backend: LedMatrix::Backend::Console.new)
m.draw_shinonome("16", 0, 0, "宝")
m.show
```

が動く状態にする。**ここが「基板が来る前にどこまで進めるか」の到達点。**

### Phase 3 — サンプルプログラム

Phase 2 のバックエンド差し替えで、そのまま実基板でも動くものを書く。

| # | サンプル | 使う機能 | 実チップ無しで作れるか |
|---|---|---|---|
| 1 | 漢字・かなスクロール | Shinonome + VRAM | ○ |
| 2 | ライフゲーム | VRAM のみ | ○ |
| 3 | フェード / 明るさデモ | 8bit PWM 直接 | △（見た目は実機必須） |
| 4 | ボタン操作のミニゲーム（スネーク等） | GPIO + VRAM | ○（入力は仮でキーボード） |
| 5 | GROVE センサ値のバーグラフ | I2C1 + VRAM | ○（Pico2-W に Grove を繋げば実機で） |
| 6 | 音と同期した表示 | PWM 音声 + VRAM | 基板待ち |

置き場所は gem の `example/` と、`mrbgems/picoruby-r2p2/examples/`（`snake_game.rb` の隣）。

### Phase 4 — 基板到着後のブリングアップ

0. **J2（SWD/UART ヘッダ）は DNP** なので、PicoProbe を使うなら 2.54mm ピンヘッダを
   自分で実装する。BOOTSEL は実装されるので UF2 のドラッグ&ドロップは常に使える
1. SDB (GPIO24) を H → 200µs 待ち → `I2C#scan` で 0x34 / 0x35 が見えるか
2. 1 ドット点灯して**上下・左右の向きを確定**（対応表自体は hardware.md §4 で確定済み）
3. GCC を低い値から上げて電流実測。IC の発熱（設計値 0.31W/個、ΔT≈16°C）も確認
4. **Open/Short 検出（0xB3–0xC4）を使った実装検査スクリプト** を書く。
   30枚配布する基板なので、半田付け不良の自動判定はそれ自体が価値になる。
   とくに **LED241（列1・行16 = U11/SW8/CS16、PWM 0x80）** はクリアランスが
   0.125mm と規則を下回る箇所なので重点的に見る（hardware.md §7-4）
5. 2 チップ間のスキャン非同期が肉眼で分かるか確認（SYNC ピンが無いため）

## 3. Gem の置き場所について

`mrbgems/picoruby-is31fl3729/` に置く（相談の上で決定）。補足:

- **`mrbgems/` 自体は submodule ではない。** submodule なのは `mrbgems/` の中の
  特定の gem だけ（`mruby-compiler`、`mruby-bin-mrbc`、`picoruby-funicular`、
  `picoruby-mruby/lib/mruby`、`picoruby-r2p2/lib/pico-sdk` など）。
  新しいディレクトリを足しても既存 submodule には一切触れない。
- upstream picoruby を追従するときも、**新規ファイルは衝突しない**。
  衝突しうるのは `build_config/r2p2-picoruby-pico2_w.rb` に
  `conf.gem core: 'picoruby-is31fl3729'` を足す 1 行だけ。
- それも避けたい場合は、**リポジトリ直下の `gems/` に置いて絶対パスで参照する**手も使える。
  動作確認済み:

  ```ruby
  conf.gem "#{MRUBY_ROOT}/gems/picoruby-is31fl3729"
  ```

  ただし `rake test:gems` は `mrbgems/` 配下を前提にしているため、
  テストの回し方を自前で用意する必要がある。**今は mrbgems/ 配下を推奨。**

## 4. リスク

| リスク | 影響 | 対策 |
|---|---|---|
| ~~(chip, SW, CS) → 物理座標の対応が不明~~ | — | **解決済み**。r1 の `netlist.ipc` と `positions.csv` から確定（hardware.md §4）。残るのは上下・左右の向きだけ |
| SDB の 200µs 待ちを忘れる | 初期化が黙って失敗する | 待ちをドライバ内部に閉じ込める |
| U11 の列反転を忘れる | 下半分だけ左右が逆に出る | 座標変換をテストで固定 |
| **全点灯 + 音声で USB 500mA 超過**。TPS2065 は 1A まで落ちないので**ハードは守ってくれない** | ブラウンアウト | GCC 初期値を低く。音声中は明るさを絞る。点灯数に応じた適応制御（hardware.md §5-4） |
| VRAM が MONO のみ | 階調表現ができない | チップ層に 8bit バッファを持たせて逃がす（1-2） |
| 2 チップのスキャン非同期 | 上下半分で見え方が違う | 4kHz スキャンなので肉眼では判別困難という調査結果。実機で確認 |
| Pico 2 W には基板のボタン(GPIO17-22)が無い | 入力系サンプルが実機確認できない | ブレッドボードにタクトスイッチ、またはシリアル入力で代替 |

## 5. 最初の一歩

Phase 1 の `mrbgems/picoruby-is31fl3729/` を作り、
`rake 'test:gems:picoruby[picoruby-is31fl3729]'` がグリーンになるところまで。
実機もクロスビルドも要らないので、ここは一気に進められる。
