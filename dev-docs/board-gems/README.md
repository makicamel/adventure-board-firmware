# 基板の全機能を Ruby から触るための Gem 棚卸し

最終目標は「基板上のすべての機能を、ユーザが Ruby だけで操作できる」こと。
そのために何を新規に作り、何を既存 gem で賄うかを整理したもの。

ピン割当の出典は `ref/picorubykaigi01-board/docs/PicoBoard_BOM_pin_assignment_20260824.xlsx`
（`docs/gpio_assignment.md` は失効。[../led-matrix-gem/hardware.md](../led-matrix-gem/hardware.md) §6 参照）。

## 1. 結論

**新規に作るのは 2 つだけ。** 残りは既存 gem がそのまま使える。

| # | Gem | 役割 |
|---|---|---|
| 1 | `picoruby-is31fl3729` | LED ドライバのチップ層。基板非依存の汎用 16×8 |
| 2 | `picoruby-picorubykaigi01` | **ボードサポート**。全機能のファサード。初心者はこれだけ触る |

音声は `picoruby-psg` + `picoruby-midibase-mml` が、文字は `picoruby-shinonome` が、
描画は `picoruby-vram` がすでに揃っている。**LED マトリクス以外は新規のドライバが要らない。**

## 2. 機能別の棚卸し

| 機能 | ハード | 既存 gem | 判定 |
|---|---|---|---|
| **LED マトリクス 16×16** | IS31FL3729 ×2、I2C0 (GPIO4/5)、SDB GPIO24 | — | ❗**新規**（[../led-matrix-gem/](../led-matrix-gem/)） |
| 漢字・かな表示 | — | `picoruby-shinonome`（16×16 JIS）、`picoruby-bdffont` | ✅ そのまま |
| 描画バッファ | — | `picoruby-vram`（線/矩形/ビットマップ、MONO） | ✅ そのまま |
| ボタン ×6（↑↓←→AB） | GPIO17〜22、10kΩ 外付けプルアップ | `picoruby-gpio` | ⚠️ 薄いラッパが要る（ボード gem 内） |
| 音声出力 | PWM GPIO10 → 2次RC → PAM8302A → LS1 | `picoruby-psg` | ✅ `PSG::Driver.select_pwm(10, 11)` で出力ピンを指定できる |
| 音楽（MML） | 同上 | `picoruby-midibase-mml` | ✅ そのまま。初心者向けの入口として最適 |
| アンプ ミュート | GPIO23（Low=停止、4.7k プルダウン） | `picoruby-gpio` | ✅ ボード gem が面倒を見る |
| ステータス LED（緑） | GPIO16 + R31 2kΩ（PWM0A） | `picoruby-gpio` / `picoruby-pwm` | ✅ 明滅もできる |
| GROVE-A（I2C） | I2C1 GPIO6/7、4.7kΩ プルアップ | `picoruby-i2c` | ✅ 設定済みオブジェクトを返すだけ |
| GROVE-B（UART or ADC） | GPIO28/29 = UART0 / ADC2・3 | `picoruby-uart` / `picoruby-adc` | ✅ どちらで使うかを選べるように |
| J1 ブレッドボードヘッダ | GPIO 2,3,8,9,11,12,13,14,15,25,26,27 | `picoruby-gpio` `-spi` `-pwm` `-adc` `-pio` | ✅ GPIO12〜15 が SPI1 一式 |
| ファイル | W25Q64（8MB） | `picoruby-littlefs` + R2P2 シェル | ✅ |
| USB シリアル | CDC ×3 | `picoruby-r2p2` | ✅ |
| BOOTSEL / RESET | SW7 / SW8 | `Machine.bootsel_pressed?` / `Machine.reboot` | ✅ |

`build_config/r2p2-picoruby-pico2.rb`（非Wireless）にはすでに
`peripherals` / `peripheral_utils` gembox と `psg` / `midibase-mml` / `shinonome` /
`keyboard` が入っている。**基板用の build_config はこれをベースにして、
上の 2 つを足すだけで足りる。**

## 3. ボードサポート gem の狙い

初心者が「触ってすぐ光る・鳴る・反応する」ところまでを数行で書けるようにする。
`docs/PicoBoard_design_policy.md` のコンセプトそのもの。

```ruby
require 'picorubykaigi01'

Board.matrix       # => LedMatrix   16×16、漢字が出る
Board.buttons      # => Buttons     :up :down :left :right :a :b
Board.speaker      # => Speaker     PSG + アンプの SD 制御込み
Board.status_led   # => GPIO / PWM
Board.grove_a      # => I2C         (GPIO6/7、プルアップは基板側)
Board.grove_b      # => UART or ADC (GPIO28/29、用途を選ぶ)
```

想定する一番短いサンプル:

```ruby
require 'picorubykaigi01'

m = Board.matrix
m.draw_shinonome("16", 0, 0, "松")
m.show
```

### ボード gem が引き受けるべきこと

ユーザに意識させたくないハードの都合を、ここに閉じ込める。

1. **SDB のタイミング** — H にしてから 200µs 待って I2C、停止は逆順
   （[hardware.md](../led-matrix-gem/hardware.md) §3-1）。忘れると黙って初期化に失敗する
2. **U11 の列反転** — 下半分だけ左右が逆（同 §4-3）
3. **★電源バジェット** — LED 全点灯 330mA + 音声 300mA + MCU 100mA = 約730mA で
   USB の 500mA を超える。**TPS2065 は 1A まで落ちないのでハードは守ってくれない**（同 §5-4）。
   → 「音を鳴らしている間はマトリクスの明るさを自動で絞る」を
   ボード gem のポリシーとして実装するのが素直
4. **ボタンのチャタリング除去** — 6本とも負論理（10kΩ プルアップ、押下で L）。
   GPIO17〜22 が連番なので一括読みできる
5. **アンプの SD** — 音を出すときだけ H。無音時に H のままだとホワイトノイズが乗る

### 実装メモ

- `AGENTS.md` の規約に従い、ライブラリ内はブロック反復（`each`/`times`）を避けて
  `while` + 整数インデックス。ivar は3回以上参照するならローカルに退避
- ボタン読みや行転送はホットパスなので特に効く

## 4. 作る順番

[../led-matrix-gem/plan.md](../led-matrix-gem/plan.md) のフェーズに、他機能を差し込む。

| 段階 | 内容 | 実基板 |
|---|---|---|
| 1 | `picoruby-is31fl3729`（レジスタ層、picotest + mock I2C） | 不要 |
| 2 | ボード gem の骨格 + `LedMatrix` + Console バックエンド | 不要 |
| 3 | `Buttons` / `Speaker` / `status_led` / `grove_*` を追加。<br>**Speaker は Pico 2 W 実機で本当に鳴らせる**（GPIO10/11 に圧電スピーカかアンプを繋ぐ） | 一部可 |
| 4 | サンプルプログラム群 | 一部可 |
| 5 | 基板用 build_config とボード定義、実基板ブリングアップ | 必要 |

Pico 2 W でどこまで行けるか:

- **LED マトリクス** … Console バックエンドで上位層とサンプルまで完成させられる
- **音声** … GPIO10/11 に外付けアンプか圧電スピーカを繋げば**実際に鳴る**。PSG も MML も実機検証できる
- **ボタン** … ブレッドボードにタクトスイッチ6個。GPIO17〜22 は Pico 2 W でも空いている
- **GROVE** … GPIO6/7 に I2C センサを繋げば実機検証できる
- **ステータス LED** … Pico 2 W のオンボード LED は CYW43 側なので、外付け LED で代用

つまり **LED マトリクス以外はほぼ実機で検証できる**。

## 5. サンプルプログラムの候補

`docs/PicoBoard_design_policy.md` の想定ユースケースに対応させる。

| # | サンプル | 使う機能 | Pico 2 W で作れるか |
|---|---|---|---|
| 1 | 漢字・かなスクロール | matrix + shinonome | ○（Console） |
| 2 | ライフゲーム | matrix | ○（Console） |
| 3 | ボタンで動かすスネーク | matrix + buttons | ○ |
| 4 | MML でメロディ再生 | speaker | ○（実際に鳴る） |
| 5 | 音に合わせてマトリクスが光る | speaker + matrix | ○ |
| 6 | GROVE センサの値をバーグラフ表示 | grove_a + matrix | ○ |
| 7 | 明るさフェード / 適応電流制御のデモ | matrix 8bit PWM | 実基板 |
| 8 | 実装検査（開放/短絡検出） | matrix | 実基板 |

## 6. Gem の置き場所

**`mrbgems/` 配下に置く。**

```
mrbgems/picoruby-is31fl3729/         チップドライバ
mrbgems/picoruby-picorubykaigi01/    ボードサポート
```

submodule の懸念について:

- **`mrbgems/` 自体は submodule ではない。** submodule なのは中の特定 gem だけ
  （`mruby-compiler`、`mruby-bin-mrbc`、`picoruby-funicular`、
  `picoruby-mruby/lib/mruby`、`picoruby-r2p2/lib/pico-sdk` など）。
  新しいディレクトリを足しても既存 submodule には一切触れない
- upstream picoruby を追従しても、**新規ファイルは衝突しない**
- `rake test:gems` や `docs/testing-guide.md` のテスト戦略が
  `mrbgems/` 配下を前提にしているので、ここに置くのが一番素直

### 代替案（動作確認済み、ただし非推奨）

リポジトリ直下の `gems/` に置いて絶対パスで参照することもできる:

```ruby
conf.gem "#{MRUBY_ROOT}/gems/picoruby-is31fl3729"
```

実際に動くことは確認済み（存在しないパスはちゃんとエラーになる）。
upstream のツリーを一切汚さない利点はあるが、
`rake test:gems` が使えなくなるので今は採らない。

### build_config について

- **Pico 2 W での開発中**は `build_config/r2p2-picoruby-pico2_w.rb` に
  `conf.gem core:` を 2 行足す。upstream ファイルへの変更はこの 2 行だけ
- **基板用**には `build_config/r2p2-picoruby-pico2.rb` をベースに新しい config を作る。
  そこは新規ファイルなので衝突ゼロ
- ⚠️ ただし `tasks/picoruby/r2p2.rake` は
  `%w[pico pico_w pico2 pico2_w]` を決め打ちでループしてタスクを生成している。
  独自ボード名を足すならこのリストに手を入れる必要がある（upstream ファイル）。
  当面は `pico2` の名前のまま使うか、そこだけ差分を持つか、いずれ判断が要る
- ⚠️ 独自の RP2350A 設計なので、pico-sdk のボードヘッダ
  （`PICO_BOARD_HEADER_DIRS`）もいずれ必要（`docker/README.md` に既述）
