# ライブラリ

`AdventureBoard` は、基板の部品をプログラムから使うためのライブラリです。
基板の `/lib/adventure_board.rb` と `/lib/adventure_board/` に入っていて、`cat` で中を読めます。
コンソールの「▸ ライブラリのコードを見る」でも同じものが読めます。

```ruby
require 'adventure_board'
GC.start

matrix = AdventureBoard.matrix     # 使う部品だけを取り出す
```

部品は、最初に取り出したときに読み込まれます。使わない部品は読み込まれないので、メモリを節約できます。

| 取り出し方 | 部品 |
|---|---|
| `AdventureBoard.matrix` | [LED マトリクス](#ledmatrix) |
| `AdventureBoard.buttons` | [ボタン](#buttons) |
| `AdventureBoard.speaker` | [スピーカー](#speaker) |
| `AdventureBoard.status_led` | [ステータス LED](#statusled) |
| `AdventureBoard.grove_i2c` | [GROVE1 の I2C](#grove) |
| `AdventureBoard.grove_link(role:)` | [GROVE2 で基板どうしをつなぐ](#grove) |
| `AdventureBoard.grove_uart` | [GROVE2 の UART](#grove) |

## LedMatrix

16×16 の LED マトリクス。

### 1 つずつ光らせる

座標は `(1, 1)` 〜 `(16, 16)`、明るさは 0〜255（見た目に比例するよう補正される）。

| 命令 | すること |
|---|---|
| `set(x, y, 明るさ = 255)` | 1 つの明るさを決める |
| `clear` | 全部消す |
| `fill(明るさ = 255)` | 全部を同じ明るさにする |
| `show` | ここまでの変更を LED に送る。**これを呼ぶまで光らない** |
| `brightness = 値` | 全体の明るさの上限（0〜0x40、最初は 0x20）。上げると電気をたくさん使う |

### 描く

座標は `(0, 0)` 〜 `(15, 15)`。描いたあと `blit` で LED マトリクスに写し、`show` で送る。

| 命令 | すること |
|---|---|
| `clear_drawing` | 描く場所を消す |
| `set_pixel(x, y, 明るさ)` | 点 |
| `draw_line(x1, y1, x2, y2, 明るさ)` | 線 |
| `draw_rect(x, y, 幅, 高さ, 明るさ)` | 四角の枠 |
| `draw_text(文字, x = 0, y = 0, font: "go16")` | 文字。フォントは `"go16"`（ゴシック）`"min16"`（明朝）`"go12"` `"min12"` `"maru12"`（12 ドット） |
| `pen = 明るさ` | 明るさを省いたとき、と文字の明るさ |
| `blit` | 描いたものを LED マトリクスに写す |

## Buttons

6 つのボタン。名前は `:up` `:down` `:left` `:right` `:a` `:b`。
押されたことは基板が覚えておくので、短く押しても取りこぼさない。

| 命令 | 返すもの |
|---|---|
| `each_press { \|name\| ... }` | 押されたボタンを古い順に 1 つずつ |
| `take_press` | 押されたボタンを 1 つ。無ければ `nil` |
| `presses_waiting` | まだ取り出していない数 |
| `clear_presses` | 覚えている押下を捨てる |
| `pressed?(name)` | いま押されているか |
| `pressed` | いま押されているボタンの一覧 |
| `any?` | どれか 1 つでも押されているか |

## Speaker

スピーカー。音は 3 つまで重ねられる。

| 命令 | すること |
|---|---|
| `reset` | 音量・音色などを最初の状態に戻す。音を鳴らすプログラムの最初に |
| `play_mml(mml, loop: false)` | MML の曲を鳴らす。配列で渡すと同時に鳴らす（3 つまで）。`loop: true` でくり返す |
| `playing?` | 曲が鳴っているか |
| `stop` | 止める |
| `note_on(番号, velocity: 100)` | 1 音鳴らし始める。60 が真ん中のド |
| `note_off(番号)` | その音を止める |

MML の書き方は [チュートリアル 5](/tutorial/05-sound#mml)。

## StatusLed

USB の近くの緑の LED。

| 命令 | すること |
|---|---|
| `on` / `off` | 点ける・消す |
| `toggle` | 点いていれば消し、消えていれば点ける |
| `on?` | 点いているか |

## GROVE

| 命令 | 返すもの |
|---|---|
| `AdventureBoard.grove_i2c(frequency: 100_000)` | GROVE1 の `I2C`（GPIO6 / GPIO7）。I2C のセンサなどに |
| `AdventureBoard.grove_link(role: :a)` | GROVE2 で同じ基板どうしをつなぐ。2 枚で `:a` と `:b` に分ける。ふつうのケーブルでつながる |
| `AdventureBoard.grove_uart(baudrate: 115200)` | GROVE2 の `UART`（TX = GPIO28、RX = GPIO29） |

使い方はサンプルの一覧の「実機専用」のもの（`grove_link_chat.rb` など）を見てください。

## そのほか

PicoRuby の部品も、そのまま使えます。

| | |
|---|---|
| `GPIO.new(番号, GPIO::OUT)` / `GPIO::IN \| GPIO::PULL_UP` | GPIO（[チュートリアル 7](/tutorial/07-breadboard)） |
| `sleep_ms(ミリ秒)` | 待つ |
| `Machine.uptime_us` | 起動してからの時間（マイクロ秒）。時計で速さを決めるときに |
| `rand(n)` | 0〜n-1 のでたらめな数 |
