# 検証レポート — 基板 2 枚の GROVE リンク

2026-09-03、Raspberry Pi Pico 2 W 1 枚。設計は [plan.md](plan.md)。

**結論: PIO で UART を作り、受信は DMA のリングバッファで受ける。
実機ループバックで検証済み。基板 2 枚での確認だけが残っている。**

以下は結論に至るまでの経緯。**一度作って捨てた方式**も、そこで得た数字も残す。
同じ判断を繰り返さないため。

---

## 0. 制約

GROVE-B（J5）は 4 ピン、信号は 2 本。

| | GPIO | ハードウェア UART での役割 |
|---|---|---|
| J5.1 | 29 | UART0 **RX** |
| J5.2 | 28 | UART0 **TX** |

RP2350 のピンマルチプレクサは **UART の役割をピン番号で固定**する。
GPIO28 は TX にしかなれず、GPIO29 は RX にしかなれない。Grove ケーブルは
ストレート（1↔1、2↔2）なので、**2 枚繋ぐと TX 同士がぶつかる**。

I2C（GROVE-A、GPIO6/7）は使えない。**`picoruby-i2c` にスレーブ実装が無い**。

PIO なら**どのピンでも入力にも出力にもできる**ので、片方だけ TX/RX を
入れ替えればストレートケーブルで噛み合う。それが「役割」。

---

## 1. 配線ゼロで検証できることに気づいた

**TX と RX に同じピンを指定するとループバックになる。** PIO は自分が駆動して
いるパッドをそのまま読めるので、**ジャンパ線も 2 枚目の基板も要らない**。

これで基板が来る前に、送受信の全部を実機で詰められた。

GPIO15 を使った。Pico 2 W で空いていてボードレイヤも使わない。
**本番の GPIO28/29 は Pico 2 W では試せない**——GPIO29 は CYW43 のクロックで
ヘッダに出ていない（GPIO24＝SDB も同様に WL_D）。実基板は無線なしの RP2350A。

---

## 2. 第 1 段: `picoruby-pio` の Ruby アセンブラで作った

pico-sdk の `uart_tx.pio` / `uart_rx.pio` を `picoruby-pio` の DSL に移した。

```ruby
UART_TX = PIO.asm(side_set: 1, side_set_optional: true) do
  wrap_target
  pull                        side: 1, delay: 7
  set :x, 7,                  side: 0, delay: 7
  label :bitloop
  out :pins, 1
  jmp :bitloop, cond: :x_dec, delay: 6
  wrap
end
```

命令語は **pico-sdk が生成するものと完全一致**した
（TX `0x9fa0 0xf727 0x6001 0x0642`、RX `0x2020 0xea27 0x4001 0x0642`）。
この 8 語がのちに C 版へそのまま移る。

計画時に「未確認」と書いた 4 点はすべて想定どおりだった。

| | |
|---|---|
| `PIO.asm` のブロック DSL の `side:` / `delay:` | ✅ |
| `get_nonblocking` の戻り（nil 返し） | ✅ |
| `instructions[0]` で取った 1 命令の `exec` | ✅ TX の起動前 High に使える |
| 2 本の SM を同じ PIO ブロックに載せる | ✅ `origin: -1` で自動配置 |

gem が面倒を見てくれない 2 点は計画どおり自分で入れた。

- **TX ピンは起動前 Low = ブレークに見える。** `exec` で `set pins, 1` を打つ
- **入力ピンにプルアップが入らない。** 未接続だと線が浮いてゴミを拾う

### 動いた。ただし行が届かなかった

```
byte sweep: 0 wrong out of 127     ← ビット順もフレーミングも正しい
got: nil                            ← "hello\n" が届かない
```

**受信 FIFO は 4 ワードしかない。** 6 バイトを一気に送って誰も読まなければ
溢れる。バイトスイープが通っていたのは 1 バイトずつ読んでいたから。

2 つ直した。

- **FIFO を寄せる。** TX と RX は別のステートマシンで、それぞれ使わない側の
  FIFO を持っている。`fifo_join: PIO::FIFO_JOIN_TX` / `..._RX` で 8 段
- **送信中も受信を吸う。** `write` が 1 バイトごとに `pump` を挟む

これで `"hello"` も 20 バイトの行も通った。

### 速度を測ったら、遅かったのは自分のコードだった

| | 実測 |
|---|---|
| Ruby が FIFO を見に行く速さ | **76,400 回/秒**（1 回 13µs） |
| 115200 でのバイト間隔 | 87µs |
| スループット | 1,872 → **2,453 バイト/秒** |
| 一気に 32 バイト送って残った数 | **9**（FIFO 8 段 + シフトレジスタ 1） |

ポーリング自体は 6.7 倍の余裕がある。詰まっていたのは 2 箇所とも自分のコード:

- `@partial += char` が 1 バイトごとに新しい String を作っていた
  （行が長いほど二次的に遅くなる）→ `<<` の追記に
- `write` が 1 バイトずつ送り、`string[i]` が毎回 String を作っていた
  → 4 バイトずつに

### API の罠を 1 つ見つけた

`write` は送信しながら受信 FIFO を行バッファへ吸う。**行の API と生の API を
混ぜると、自分の送信が相手のバイトを食う。** バイトスイープが 1 件落ちて
気づいた（0 → 1 → 直して 0）。行の組と生の組に分けた。

### 数十バイトの表を作った

57 バイトのゲーム状態風メッセージで、送信の塊と受信のポーリング間隔を振った。

| 送信の塊 | 受信ポーリング間隔 | 結果 | 所要 |
|---|---|---|---:|
| 4B | 2ms | OK | 56ms |
| 8B | 2ms | OK | 41ms |
| 8B | 20ms | OK | 197ms |
| **16B** | 20ms | **欠落** | — |
| 4B | 20ms | OK | 337ms |
| `write()` | — | OK | 22ms |

**8 バイトを超える塊だけが落ちる。間隔は関係ない。** きれいな規則が出たので、
「受信側が次に見に来るまでに 8 バイトを超えて載せない」を作法にすればよい、
と結論した。

---

## 3. その結論は間違っていた

指摘を受けた。**8 バイトのハードウェア FIFO を Ruby のポーリングで守るのは、
設計として成立していない。**

- GC が一度走れば、`matrix.show` の I2C が数 ms 伸びれば、それだけで落ちる
- しかも**黙って落ちる**。PIO に overflow フラグは無い
- 上の表の「OK」は**ジッターの無い理想条件**の値でしかない
- そして 57 バイトに 200〜300ms は、**33ms のフレームに毎回状態を送る用途には論外**

緩和策（ボーレートを落とす、送信側でペースを作る、ACK でフロー制御）は
どれも「Ruby が間に合う」という前提を延命するだけだった。

**受信経路からプロセッサを外す以外に道は無い。**

---

## 4. 第 2 段: DMA で受ける

事例はあった。**[dgatf/Pio-UART-RX-RP2040](https://github.com/dgatf/Pio-UART-RX-RP2040)**
が分かりやすい実例で、手口は定石。

```c
channel_config_set_ring(&d, true, RX_BITS);              /* 書き込みアドレスが回る */
channel_config_set_dreq(&d, pio_get_dreq(pio, sm, false));
channel_config_set_chain_to(&d, reload_chan);            /* 永久に止まらない */
dma_channel_configure(rx_chan, &d, rx_buffer,
                      (const uint8_t *)&pio->rxf[sm] + 3, /* 上位バイトだけ */
                      RX_COUNT_MAX, false);
```

4 つの要点:

1. **リングは DMA のハードウェア機能。** バッファを自分のサイズ境界に
   アラインするだけで、書き込みアドレスが折り返す
2. **2 本目の DMA が転送カウンタを書き戻す**（`chain_to`）ので転送が終わらない
3. `DMA_SIZE_8` で **FIFO ワードの上位バイトだけ**読む。autopush が
   右シフトで押し込むので、バイトはそこにある
4. **カウンタの差分で available と overflow が分かる。**
   ポーリング版に無かった「落としたことに気づく」手段が手に入る

新しい gem [`mrbgems/picoruby-pio-uart`](../../mrbgems/picoruby-pio-uart/) に
した。PIO のステートマシンは自分で持つ（`picoruby-pio` には依存しない）。
命令語は第 1 段で検証済みのものをそのまま埋め込んだ。

送信は C のループで FIFO に押し込むだけにした。**送信では何も失われない**
——ペースはこちらが決めているので。57 バイトで 5ms ブロックする。

---

## 5. 実装で詰まったところ

順に。**ハードの罠 4 つ、自分の誤診 1 つ、ビルドの作法 2 つ。**
ハードの罠はどれも「世の中の例をそのまま持ってくると外れる」もので、
誤診はエラーメッセージの読み方を間違えたもの。

### ハードの罠（PIO + DMA 編）

**PIO のピン方向はステートマシン間で共有される。**

参照実装をまねて受信側で
`pio_sm_set_consecutive_pindirs(pio, rx_sm, rx_pin, 1, false)` を呼んだら、
**受信が全く動かなくなった**。TX と RX が同じピンを指すループバックでは、
この 1 行が**送信側の出力を殺す**。PIO のピン方向は SM ごとの状態に見えて、
実際の GPIO の出力イネーブルは共有で、最後に書いた方が勝つ。

参照実装は別ピン前提だったので踏まなかった罠。`pio_gpio_init` の後は
既定で入力なので、**この行はそもそも要らない**。外した。

**RP2350 の `TRANS_COUNT` は上位 4 ビットが MODE。**

外してもまだ受信できなかった。原因はこれ。

```
DMA_CH0_TRANS_COUNT_MODE_BITS          0xf0000000
DMA_CH0_TRANS_COUNT_MODE_VALUE_NORMAL  0x0
DMA_CH0_TRANS_COUNT_MODE_VALUE_ENDLESS 0xf
DMA_CH0_TRANS_COUNT_COUNT_BITS         0x0fffffff
```

**RP2040 では 32 ビット全部がカウント**なので、世の中の例はみな
`0xffffffff` を書く。それを RP2350 に持ってくると **MODE=ENDLESS**
——「カウントを減らさずに永久に走る」——になる。

つまり**バッファは正しく埋まっているのに、カウンタが「0 バイト受信」と
言い続ける**。データが流れていないように見えるので、PIO 側を疑って一往復した。

`0x0fffffff` が MODE=NORMAL の最大値。この回線速度なら 6 時間半ぶん。
RP2040 でも同じコードで動く（ただ上限が小さくなるだけ）。

---

### ハードの罠（`UART` ユニット編）

**埋まっているハードウェアアラームを `hardware_alarm_claim()` すると panic する。**
プロデューサに 3 番を決め打ちしたら、スクリプトが 1 行目も出さずに固まった。
0 は `picoruby-machine` のティック、1 と 2 は `picoruby-psg`、
**3 は SDK の既定アラームプール**。`hardware_alarm_claim_unused()` で取る。

**`UART` のリングは既定 256 バイトで、DMA リング（512）より小さい。**
渡さないと、ハードが受け取ったものが Ruby へ渡る途中で落ちる——
10 通送って 4 通しか届かず、`rx_overflow_count` が 325 になった。
リングが 2 段になったのだから**上流より下流を細くしてはいけない**。
`GroveLink` は 1024 を渡す。

### 自分の誤診 — 「型が無い」で 2 回作り直した

`UART` のユニットを書いているとき、プロデューサのタイマでこう出た:

```
error: expected '=', ',', ';', 'asm' or '__attribute__' before '*' token
  200 | static alarm_pool_t *pio_producer_pool;
```

`alarm_pool_t` が見えていない、と読んだ。`pico/time.h` は include してあり、
同じ型を使う `picoruby-psg` は通っている。include 順を疑い、**SDK の既定
アラームプールを使う形に書き換えた**（プール型を使わずに済むので）。

次はこう出た:

```
error: expected '=', ',', ';', 'asm' or '__attribute__' before 'pio_producer_timer'
  202 | static repeating_timer_t pio_producer_timer;
```

`repeating_timer_t` も見えていない。SDK のタイマ API を諦めて、
**`picoruby-machine` と同じタイマレジスタ直叩きに書き換えた**。

三度目はこう出た:

```
error: two or more data types in declaration specifiers
  209 | static bool pio_producer_running;
      |        ^~~~
error: variable or field 'pio_producer_running' declared void
```

**`bool` が「型が 2 つ」で、変数が `void` で宣言されている。**
`bool` は同じファイルの 63 行目で問題なく使われている。ここでようやく
「型が無い」のではなく**その手前が閉じていない**と気づいた。

原因は私の編集だった。挿入位置が `UART_open` の**戻り値型 `void` と関数名の間**で、
宙に浮いた `void` が次の宣言に食い込んでいた。

```c
void          ← これ
/* 私が挿入したコメントと関数 */
...
void
UART_open(int unit_num, ...)
```

`void static alarm_pool_t *x;` が「`*` の前に `=` が要る」、
`void static bool x;` が「型が 2 つ」。**3 つのエラーは全部同じ 1 つの原因**で、
API を 2 回書き換えたのは無駄だった（しかも同じ間違いを 2 箇所でやっていて、
1 つ直したらもう 1 つが出た）。

**教訓。** GCC の "two or more data types in declaration specifiers" が
健全な `bool` を指したら、**指された行ではなく手前を読む**。
「未知の型」に見えるエラーも、直前の宣言が閉じていないだけのことがある。
症状に合わせて実装方針を変える前に、**同じファイルの別の場所で同じ型が
通っているか**を見る——通っていれば、型の問題ではない。

（結果として残った「タイマレジスタ直叩き」は `picoruby-machine` と同じ手で
悪くないので、そのままにしてある。理由付けが間違っていただけ。）

### ビルドの作法

**Ruby 側の無い gem でも gem のフックは要る。** C だけの gem にしたら
リンクで落ちた:

```
undefined reference to `mrb_picoruby_pio_uart_gem_init'
```

`src/pio_uart.c` に空の `_gem_init` / `_gem_final` を置いた。
同じ理由で、`src/` にファイルが 1 つも無い gem も避けた
（このファイルはホスト側でもコンパイルされるので、PIO も DMA も参照できない）。

**`ports/rp2040/*.c` は CMake が自動で拾う。** `mrbgems/*/ports/rp2040/*.c` の
glob があるので、新しい gem のポートを足すのに `CMakeLists.txt` を触る必要は無い。

## 6. 結果

`devtest/dma_loopback.rb`:

```
buffer is 512 bytes
burst 200: 200 bytes, intact               ← Ruby は一切見ていない
after 500ms idle: 200 bytes, intact        ← 500ms 放置しても無傷
overran with 800: kept 512, overflow: true ← 黙って落とさず報告する
byte sweep 1..255: 0 wrong
write 200 bytes: 17076us = 11,712 bytes/s  ← ほぼ回線速度（11,520）
```

`devtest/link_message.rb`（57 バイトのゲーム状態、`UART` ユニット経由）:

```
unit is a UART                                  ← 普通の UART
state: intact                                   ← 送信後 200ms 誰も読まなくても無傷
send took 4979us for 57 bytes                   ← 送信は 5ms
lost: 0
10 messages sent unread: 10 arrived, lost: 0    ← 580 バイトを誰も読まずに全部
irq delivered: ["through-irq"]                  ← UART#irq がそのまま動く
```

**512 バイトは、この 57 バイトの状態なら 9 フレームぶんの猶予**にあたる。
毎フレーム読むプログラムなら溜まりようがない。溢れたときは
`UART#rx_overflow_count`（`GroveLink#lost`）が言う。

### ポーリング版との差

| | ポーリング版 | DMA 版 |
|---|---|---|
| 受信バッファ | 8 バイト | **512 バイト** |
| 誰も読まずに 500ms 放置 | 8 バイトだけ残る | **無傷** |
| 落としたときの通知 | **無い（黙って消える）** | `lost?` が true |
| 送信速度 | 2,453 B/s | **11,712 B/s** |
| ジッター耐性 | 実質なし | DMA 512 + UART 1024 バイト |
| API | 独自 | **普通の `UART`**（`gets` / `irq` 込み） |

---

## 7. メモリ

| | |
|---|---|
| `lib/picorubykaigi01/grove_link.rb` | 2,466 バイト（gem 化で 5,870 から半減） |
| `mrbgems/picoruby-pio-uart/ports/rp2040/pio_uart.c` | 10,801 バイト（フラッシュ。ヒープを食わない） |

`examples/grove_link_chat.rb` は 4 本 require する
（`picorubykaigi01` / `led_matrix` / `buttons` / `grove_link`）。
今のところ**一番重いサンプル**:

| | used | free | max_free |
|---|---:|---:|---:|
| 読み込み後 | 325,824 | 79,304 | 19,616 |

**C に移したぶんヒープが軽くなった。** PIO プログラムの構築も行バッファの
管理も C 側に移ったので、Ruby 側は行の組み立てだけになっている。

実機では `matrix.clear` で `I2C write failed (IOError)` になるが、これは
LED ドライバの載っていない Pico 2 W なので**正しい失敗**。コンパイルが通って
メモリに収まることは、これで確かめられている。

---

## 8. まだ確かめていないこと

**基板 2 枚での通信。** 試作基板が来てから:

- ストレートケーブルで本当に噛み合うか
- 役割を逆に選んだときに何が見えるか（TX 同士が押し合う）
- 115200 が安定するか（ケーブル長と容量次第）
- 2 枚が同時に喋ったときの挙動

**送信の 5ms ブロック。** 33ms のフレームの 15%。送信も DMA 化できるが、
失われるものは無いので後回しにしてある。TX を DMA にするなら、
autopull を 8 ビット閾値にして 1 ワード 4 バイトで流すのが素直。
