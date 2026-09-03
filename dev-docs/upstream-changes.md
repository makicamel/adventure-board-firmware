# upstream に入れた変更

この repo は [picoruby](https://github.com/picoruby/picoruby) のフォークで、
基板固有のものは新しいディレクトリに置いている。**upstream のファイルへの変更は
ここに全部載せる。** マージのときに何を見ればよいかが分かるように。

新規ディレクトリ（衝突しないもの）:
`mrbgems/picoruby-is31fl3729/`、`mrbgems/picoruby-pio-uart/`、
`sim/`、`dev-docs/`、`tools/`、`docker/`、`lib/picorubykaigi01*`、
`examples/`、`tasks/docker.rake`、`tasks/sim.rake`。

---

## 1. ビルドの入口

| ファイル | 変更 |
|---|---|
| `Rakefile` | `tasks/docker.rake` と `tasks/sim.rake` を load する **2 行** |
| `build_config/r2p2-picoruby-pico2.rb` | `conf.gem core: 'picoruby-is31fl3729'` **1 行** |
| `build_config/picoruby-wasm.rb` | シミュレータ用に描画・フォント gem を追加 |

## 2. `build_config/r2p2-picoruby-pico2_w.rb` — gembox を削った

```ruby
- conf.gembox "networking"
- conf.gem core: 'picoruby-ble'
- conf.gem core: 'picoruby-ble-uart'
- conf.gem core: 'picoruby-keyboard'
+ conf.gem core: 'picoruby-is31fl3729'
+ conf.gem core: 'picoruby-pio-uart'
```

**理由。** 起動しただけでヒープが 290KB 使われていて、`/lib` のボードライブラリが
読めなかった。LED・音・ボタン・GROVE の学習用基板にネットワークと BLE は要らない。
削ると **220KB / 最大連続 161KB** になり、読めるようになる。
→ [device-bringup/require-memory.md](device-bringup/require-memory.md)

## 3. `picoruby-r2p2/ports/rp2040/fault_handler.c` — 固まらずに再起動する

末尾がこうだった:

```c
while (1) {
  __asm volatile("bkpt #0");
}
```

**`bkpt` はデバッガが halt しているときだけ止まる命令**で、繋がっていなければ
フォールトにエスカレートする。すでに HardFault の中なので **double fault**、
そしてロックアップ。SWD からメモリも読めなくなり、電源を抜くしかなくなる。
prod は stdio が無効なので、その上のレジスタダンプもどこにも出ていない。

変更:

- naked ハンドラの冒頭で SIO CPUID を見て `__StackTop` / `__StackOneTop` に
  MSP を積み直す（スタック溢れで来た場合にハンドラ自身が動けるように）
- `DHCSR.C_DEBUGEN` を見て、**デバッガが居るときだけ `bkpt`**。
  居なければ `stdio_flush()` して `watchdog_reboot(0, 0, 0)`

→ [device-bringup/flashing-from-wsl.md](device-bringup/flashing-from-wsl.md)

## 4. `picoruby-r2p2` — `/lib` とサンプルをファームで運ぶ

| ファイル | 変更 |
|---|---|
| `ports/rp2040/main.c` | `picorb_install_system_files()` の呼び出し **2 行** |
| `cmake/CMakeLists.txt` | `tools/gen_system_files.rb` を configure 時に走らせる |
| `ports/rp2040/system_files.{c,h}` | **新規**。無いファイルと古いファイルを書き出す |

**理由。** 配布は UF2 1 本にしたい。UF2 は 0x10000000〜0x10245900 で、littlefs は
0x10380000 なので、焼いてもファイルは届かない。ファームが内蔵して起動時に書く。

ウォッチドッグで囲ってある。**USB より前に走るので、そこで止まったボードは
何にも答えない**（littlefs が壊れていると `lfs_stat` が返らないことがある)。
次の起動でやりかけだと分かったら、丸ごと諦めてシェルまで進む。

## 5. `picoruby-vram` — 8bit 階調

| ファイル | 変更 |
|---|---|
| `src/vram.c` | `gray8` のピクセル関数 3 つと `display_page_init_format`、`display_draw_bytes` に色 |
| `src/mruby/vram.c` / `src/mrubyc/vram.c` | `layout: :gray8`、`draw_bitmap` / `draw_bytes` の `color:` |
| `sig/vram.rbs` / `README.md` | 上に追随 |

**理由。** 1bit だと LED の明るさが使えず、サンプルが書きにくかった。
ピクセル形式は元から関数ポインタで切り替わる作りだったので、
**1 形式足すだけ**で済んだ。既存の `:vertical` / `:horizontal` は変わらない。

## 6. `picoruby-uart` — PIO のユニットを足した（**184 行**）

| ファイル | 変更 |
|---|---|
| `include/uart.h` | `#define PICORB_UART_PIO_UART0 2` と `UART_UNIT_MAX` を 2→3。**9 行** |
| `ports/rp2040/uart.c` | ユニットの追加。**175 行** |
| `picoruby-irq/include/irq.h` | `IRQ_SRC_UART2,` **1 行** |

```ruby
UART.new(unit: :PIO_UART0, txd_pin: 28, rxd_pin: 29, baudrate: 115_200)
```

**理由がこの変更の全部。** ピンマルチプレクサは UART の役割をピン番号で固定する
ので、同じ基板 2 枚をストレートケーブルで繋ぐと TX 同士がぶつかる。PIO なら
どちらのピンにどちらの役割も置けるので、片方だけ入れ替えれば噛み合う。

**それを別クラスにはしなかった。** この基板で覚えたことが素の R2P2 で
通じなくなるからで、それは教材として失敗だ。`gets` も `irq` も
`bytes_available` も `rx_overflow_count` も、**同じ `UART` の同じメソッド**が動く。
違うのは `unit:` に何を渡すかだけで、それは `RP2040_UART0` と `RP2040_UART1` を
選ぶのと同じ性質の指定。

### 変更の中身

`picoruby-uart` は**コアとポートが分離**されている。

```
ポート ── UART_pushBufferAt ─▶ コアのリングバッファ ─▶ read/gets/getbyte/bytes_available
      └── UART_signal_rx ───▶ イベント橋 ────────▶ irq
```

だからポートにユニットを 1 つ足すだけで全メソッドが動く。足したもの:

- **エンジンへの weak な入口。** 実装は `mrbgems/picoruby-pio-uart`。
  weak なので、**その gem を積まないビルドもそのままリンクでき**、
  ユニットを要求すると「使えない」と答える
- 名前 `"PIO_UART0"` の解決。ピン表の検査は**通さない**（どのピンでもよいのが
  PIO の取り柄なので、表に載っていないことは意味を持たない）
- `UART_open` の分岐と、**プロデューサ**
- ハード固有の操作（`set_format` / `set_flow_control` / `break`）の分岐。
  PIO は 8N1 のみでフロー制御は無いので、既定以外は静かに適用されない

### プロデューサ

ハードウェア UART は割り込みでリングを埋める。PIO には DMA があるが、
**DMA は転送が終わるまで何も上げず、この転送は終わらない**。
そこでハードウェアアラームで 1ms ごとに DMA リングからコアのリングへ移し、
`UART_signal_rx` を打つ。これで `UART#irq` がハードウェアユニットと同じに見える。

**1ms は遅延であって欠落ではない。** DMA リングは誰も汲みに来なくても
512 バイト持っている——それが DMA にした理由そのもの。

アラーム番号は `hardware_alarm_claim_unused()` で取る。**0 は
picoruby-machine のティック、1 と 2 は picoruby-psg、3 は SDK の既定
アラームプール**で、埋まっている番号を `hardware_alarm_claim()` すると panic する。

→ [grove-link/report.md](grove-link/report.md)

---

## 触っていないもの

`mrbgems/` 自体はサブモジュールではない（サブモジュールは中の特定 gem だけ）。
`picoruby-pio`、`picoruby-i2c`、`picoruby-shell`、`picoruby-require` などは
**一切変更していない**。

`picoruby-require` が `Sandbox` を回収しないのは把握しているが、
**upstream の仕様変更になるので触っていない**。サンプル側で
`require` 1 本ごとに `GC.start` を呼んで凌いでいる。
→ [device-bringup/require-memory.md](device-bringup/require-memory.md)

⚠️ `tasks/picoruby/r2p2.rake` はボード名を決め打ちでループしてタスクを生成する。
独自ボード名を足すにはここに手を入れる必要があり、**まだ手を入れていない**
（`USE_WIFI=1` もここでボード名ごとに決め打ちされている）。
