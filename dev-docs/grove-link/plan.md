# PIO で UART を作って、基板 2 枚を繋ぐ

## なぜ普通の UART では駄目か

GROVE-B（J5）は 4 ピン。信号は 2 本:

| | GPIO | ハードウェア UART での役割 |
|---|---|---|
| J5.1 | 29 | UART0 **RX** |
| J5.2 | 28 | UART0 **TX** |

RP2350 のピンマルチプレクサは **UART の役割をピン番号で固定**している。
4 の倍数のピンが TX、その次が RX。GPIO28 は TX にしかなれず、GPIO29 は
RX にしかなれない。**入れ替えられない。**

Grove ケーブルはストレート（1↔1、2↔2）なので、2 枚を繋ぐと
**GPIO28 同士＝ TX 同士**がぶつかる。だから今の
[`examples/grove_uart_chat.rb`](../../examples/grove_uart_chat.rb) は
クロスケーブルを要求している。

ワークショップでケーブルを配って回るのは事故のもとで、しかも間違えても
**「何も起きない」だけ**で原因が見えない。

## なぜ I2C ではないか

GROVE-A（GPIO6/7、基板に 4.7kΩ プルアップ）なら straight で繋がるが、
**`picoruby-i2c` にスレーブ実装が無い**（マスタのみ）。2 枚を I2C で繋ぐには
片方がスレーブになる必要があるので、この道は塞がっている。
GROVE-A はセンサ用に残す。

## PIO なら役割を入れ替えられる

PIO は**どのピンでも**入力にも出力にもできる。片方の基板が
TX=GPIO29 / RX=GPIO28 で喋れば、ストレートケーブルのまま噛み合う。

```
       J5.2 (GPIO28)
  A ───────────────── B        A: TX=28  RX=29   （そのまま）
       J5.1 (GPIO29)           B: TX=29  RX=28   （入れ替え）
  A ───────────────── B
```

**2 枚とも PIO を使い、役割だけ起動時に選ぶ。** 片方をハードウェア UART に
することもできるが（役割 A はちょうど UART0 の配置）、コードが 2 系統になって
教材として損なので採らない。

`picoruby-pio` は `peripherals` gembox に入っているので**追加の gem は不要**。

## PIO プログラム

pico-sdk の `uart_tx.pio` / `uart_rx.pio` を `picoruby-pio` の DSL に移したもの。
1 ビット 8 サイクルなので、ステートマシンのクロックは **ボーレート × 8**。

```ruby
# 送信。side-set で TX ピンを直接叩く。
#   pull で 1 バイト取り、ストップビット（High）を保ったまま待つ
#   set x,7 と同時に Low を出す＝スタートビット
#   8 回まわして LSB から 1 ビットずつ
UART_TX = PIO.asm(side_set: 1, side_set_optional: true) do
  wrap_target
  pull                        side: 1, delay: 7
  set :x, 7,                  side: 0, delay: 7
  label :bitloop
  out :pins, 1
  jmp :bitloop, cond: :x_dec, delay: 6
  wrap
end

# 受信。スタートビットの立ち下がりを待ち、
# 10 サイクル待って最初のデータビットの「目」で拾う。
UART_RX = PIO.asm do
  wrap_target
  wait 0, :pin, 0
  set :x, 7,                  delay: 10
  label :bitloop
  in_ :pins, 1
  jmp :bitloop, cond: :x_dec, delay: 6
  wrap
end
```

ステートマシンは 1 つの PIO ブロックに 2 本同居させる。
`PIO_init` は `origin = -1` で `pio_add_program` するので、
**2 本目は自動で空いた位置に載り、wrap も補正される**。

```ruby
tx = PIO::StateMachine.new(
  pio: PIO::PIO0, sm: 0, program: UART_TX, freq: baudrate * 8,
  out_pins: tx_pin, out_pin_count: 1,
  sideset_pins: tx_pin,
  out_shift_right: true, out_shift_autopull: false, out_shift_threshold: 32
)

rx = PIO::StateMachine.new(
  pio: PIO::PIO0, sm: 1, program: UART_RX, freq: baudrate * 8,
  in_pins: rx_pin,
  in_shift_right: true, in_shift_autopush: true, in_shift_threshold: 8
)
```

読むときは autopush（閾値 8、右シフト）なので、**バイトは 32bit の上位に来る**:

```ruby
word = rx.get_nonblocking and (word >> 24) & 0xff
```

### 起動時の 2 点

**TX ピンを先に High にする。** `PIO_init` はピンを出力にするが、値は 0 なので
ステートマシンを回す前は Low ＝ブレーク信号に見える。`exec` が生の命令を
取れるので、これで潰す:

```ruby
tx.exec(PIO.asm { set :pins, 1 }.instructions[0])
tx.start
```

**RX ピンにプルアップを入れる。** 相手が繋がっていない間、線が浮いてゴミを
拾う。`PIO_init` は入力ピンのプルを触らないので、自分で:

```ruby
GPIO.new(rx_pin, GPIO::IN | GPIO::PULL_UP)
```

それでも相手の起動時に 1 バイトほど化けるのは避けにくいので、
**リンクを開いた直後に受信バッファを捨てる**。

## ボードレイヤの API

`lib/picorubykaigi01/grove_link.rb` を足す。サンプルが require するのは
これ 1 本。

```ruby
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/grove_link'
GC.start

link = board.grove_link(role: :a)   # :a はそのまま、:b は入れ替え

link.puts "u"                       # 行単位で送る
while name = link.gets              # 溜まっていなければ nil
  ...
end
```

`gets` は**ブロックしない**。サンプルは `while true` + `sleep_ms` で回るので、
届いていなければ nil を返して次に進む。行の組み立ては Ruby 側で持つ。

`Board#grove_link` は他のペリフェラルと同じく**要求されたときに作る**。
GROVE-B は ADC2/ADC3 でもあるので、リンクを開くまでアナログ側は生きている。

## 役割をどう決めるか

**両方とも、選ぶまでは送信しない。** 起動したら受信だけして待ち、
上ボタンで A、下ボタンで B。選んだ役割は LED マトリクスに出す。

- ケーブルの心配が要らない（箱のストレートで繋がる）
- 「どちらが A か」は**画面を見れば分かる**。クロスケーブルの取り違えと違って
  失敗が見える
- クライアント／サーバという概念も一緒に教えられる

⚠ 2 枚とも同じ役割を選ぶと **TX 同士が同じ線を押し合う**。RP2350 の出力は
2〜12mA に制限されているので短時間なら壊れないが、通信はできない。
画面に役割が出ているので気づけるはず。

心配なら **TX をオープンドレインにする**手がある。PIO は `out :pindirs` /
`set :pindirs` でピンの向きを動かせるので、「Low のときだけ出力、High は
入力＋プルアップ」に書き換えられる。ぶつかっても壊れない（ワイヤード AND）。
代償は内蔵プルアップ（50〜80kΩ）での立ち上がりの遅さで、**19200 以下**に
落とすことになる。まず push-pull・115200 で作り、必要なら後から。

## シミュレータでは動かない

`PIO` は C 拡張で、ブラウザの PicoRuby.wasm には無い。相手の基板も無い。
このサンプルは `examples/`（実機専用）に置く。`sim/examples/` には置かない。

## 手順

1. `lib/picorubykaigi01/grove_link.rb` — PIO プログラム、`GroveLink`、行バッファ
2. `Board#grove_link(role:, baudrate:)` — 遅延生成
3. `examples/grove_link_chat.rb` — 役割選択 → 相手のドットを動かす
4. 実機 2 枚で確認:
   - ストレートケーブルで通ること
   - 役割を逆に選んだときに何が見えるか
   - ボーレートの上限（115200 で安定するか）
   - `rx_overflow` に相当する取りこぼしが出ないか
5. 既存の [`examples/grove_uart_chat.rb`](../../examples/grove_uart_chat.rb) を
   どうするか決める。クロスケーブル版として残す価値はある
   （**ハードウェア UART の使い方**という別の教材になる）

## 実装して分かったこと（2026-09-03）

Pico 2 W 1 枚で検証した。**TX と RX に同じピンを指定するとループバックになる**
——PIO は自分が駆動しているパッドをそのまま読めるので、**ジャンパ線すら要らない**。

```
got: "hello"           OK
then: "second" "third"
long: OK               ← 20 バイト（FIFO 8 段より長い）
byte sweep: 0 wrong out of 127
```

計画時に「未確認」と書いた 4 点はすべて想定どおりだった。
`PIO.asm` のブロック DSL、`get_nonblocking` の nil 返し、
`instructions[0]` で取った 1 命令の `exec`、2 本の SM の同居。

### 想定していなかったこと — FIFO が 4 段しかない

最初の実装では `"hello\n"` が届かなかった。**受信 FIFO は 4 ワード**しかなく、
6 バイトを一気に送って誰も読まなければ溢れる。バイトスイープが通ったのは
1 バイトずつ読んでいたからだった。

2 つ直した:

- **FIFO を寄せる。** TX と RX は別のステートマシンで、それぞれ使わない側の
  FIFO を持っている。`fifo_join: PIO::FIFO_JOIN_TX` / `..._RX` で 8 段になる
- **送信中も受信を吸う。** `write` は 1 バイト送るごとに `pump` を呼ぶ。
  ループバックでも、相手が即答してくる場合でも、これで詰まらない

**それでも 8 バイトが上限**で、その先に割り込みは無い。溜まる前に読みに来ないと
黙って落ちる。サンプルのループを短く保つ理由がこれで、クラスのコメントにも書いた。
ハードウェア UART は C 側にリングバッファを持っている（`bytes_available` /
`rx_overflow_count` がある）ので、そこは PIO 版が明確に劣る。

### 速度 — FIFO は制限要因ではない

「4 ワードの FIFO で速度が出るのか」を実機で測った（115200、ループバック）。

| | |
|---|---|
| Ruby が FIFO を見に行く速さ | **76,400 回/秒**（1 回 13µs） |
| 115200 でのバイト間隔 | **87µs** |
| 実測スループット | **2,500〜2,900 バイト/秒** |
| 一気に 32 バイト送って残った数 | **9**（FIFO 8 段 + シフトレジスタ 1） |

**ポーリングは 6.7 倍の余裕がある。** 13µs で見に行けるのに、バイトは 87µs に
1 個しか来ない。だから**取りこぼす理由は「見に行かないこと」だけ**で、
FIFO の深さは連続で受けられる塊の大きさ（8 バイト）を決めているに過ぎない。

実測 2,500B/s が回線速度 11,500B/s に届かないのは、**Ruby 側の処理が重い**から。
最初の実装は 1,872B/s しか出ず、原因は 2 つとも自分のコードだった:

- `@partial += char` が 1 バイトごとに新しい String を作っていた（行が長いほど
  二次的に遅くなる）。`<<` で追記に変えた
- `write` が 1 バイトずつ送っていて、`string[i]` が毎回 String を作っていた。
  4 バイトずつに変えた（受信 FIFO 8 段の半分なら余裕がある）

**用途には十分すぎる。** ボタン 1 回が 2 バイトなので、2,500B/s は 1,000 倍以上の
余裕がある。逆に**まとまったデータを流す用途には向かない** —— 送る側が
ペースを作らないと 8 バイトで溢れる（`write` はそれをやっている）。
バルク転送ならハードウェア UART の方が上で、C 側にリングバッファがある。

### API は 2 組ある

`write` は送信しながら受信 FIFO を行バッファへ吸う。**行の API と生の API を
混ぜると、自分の送信が相手のバイトを食う**。バイトスイープが 1 件落ちて気づいた。

| 組 | |
|---|---|
| 行 | `puts` / `write` / `gets` |
| 生 | `write_raw` / `read_byte` |

### まだ確かめていないこと

**基板 2 枚での通信。** 試作基板が来てから:

- ストレートケーブルで本当に噛み合うか
- 役割を逆に選んだときに何が見えるか
- 115200 で安定するか（ケーブル長と容量次第）
- GPIO28/29 は Pico 2 W では試せない。**GPIO29 は CYW43 のクロック**で
  ヘッダに出ていない（GPIO24＝SDB も同様に WL_D）。実基板は無線なしの
  RP2350A なので問題ない
