# r1 基板の初回ブリングアップ（2026-09-06〜07）

試作基板 r1 が届いて最初に分かったことと、ファームを初めて焼いた記録。
基板側の測定と原因分析は基板リポジトリの `docs/bringup_r1_20260906.md` にあり、
ここはファームウェア側から見た話だけ。

## 基板の状態

- **USB が一切見えない。** ESD アレイ U5（H5VU25UC）が内部パススルーを持たない
  品種で、USB-C コネクタと R3/R4 の間が開放になっている。MCU 側の D+ は
  3.3V にプルアップされており、bootrom は USB ブートまで到達している
  （＝コア・XOSC・PLL・QSPI は合格）
- 他は全部正常。5V / 3V3 / 1V1 / RUN、水晶、フラッシュ（W25Q64JVSSIQ）
- `.kicad_pcb` から機械抽出して確認した配線:
  - U5 は 2↔9 / 5↔6 / 4↔7 / 1↔10 が繋がっている前提の配置
  - J2 = 1:GND / 2:SWCLK / 3:SWDIO / 4:UART_RX / 5:UART_TX。全て 22Ω 直列
  - UART_TX は U1 pin2、UART_RX は pin3 で、**GPIO0 / GPIO1**。
    `PICO_DEFAULT_UART` の既定ピンと同じなので debug ビルドの `printf` が
    改造なしで J2 に出る
  - 基板は **Pico 2 相当**（WiFi なし）。焼くのは `pico2` のビルド

## やったこと

1. PicoProbe を J2 に接続（SWD 3 本 + UART 2 本 + GND）。
   Debug Probe 付属の 3 ピン JST-SH は SWCLK/GND/SWDIO の順で、J2 は
   GND/SWCLK/SWDIO なので直挿しできない。ジャンパで組み替える
2. `rake docker:r2p2:picoruby:pico2:debug` → `rake docker:flash:picoruby:pico2:debug`
3. UART（115200bps）に起動ログが出て、`/lib` と `/home/examples` の書き出しまで
   確認できた

```
R2P2 PicoRuby starting...
Heap size: 384 KB
./mrbgems/picoruby-littlefs/lib/littlefs/lfs.c:1382:error: Corrupted dir pair at {0x0, 0x1}
[R2P2] installed /lib/picorubykaigi01.rb (1802 bytes)
...
[R2P2] installed /etc/picorubykaigi01-files (16 bytes)
R2P2 PicoRuby starting...
Heap size: 384 KB
```

`Corrupted dir pair` は空のフラッシュを初めてマウントしたときの littlefs の
出力で、そのままフォーマットされる。異常ではない。

最後の起動でプロンプトが出ないのは正常。R2P2 のシェルは USB CDC にしか
繋がっていない（`picorb_hal_write` / `picorb_hal_getchar` が TinyUSB 直結）。
`pico_enable_stdio_uart` は pico-sdk の `printf` だけを制御する。

## 踏んだ穴

### この基板では SWD の halt が効かない

openocd が両コアを `unknown` と報告し、`halt` が

```
Warn : [rp2350.dap.core0] target was in unknown state when halt was requested
Error: [rp2350.dap.core1] not halted
```

で失敗する。`mdw` / `mww` は通る。フラッシュの `program` も verify まで通る。
Pico 2 W では halt が通っていたので基板固有の差。22Ω の直列抵抗とジャンパ線、
Debug Probe のファーム（2.0.0）のどれかを疑っているが未解明。
gdb でのデバッグには支障になる。

### `flash.sh` のウォッチドッグ再起動が halt 前提だった

書き込み後の再起動は `init; halt; mww ...` で、halt が失敗すると後ろの
`mww` が走らない。halt を外して

```
openocd -f interface/cmsis-dap.cfg -f target/rp2350.cfg \
  -c "init" -c "mww 0x40018008 0x01fffff3" -c "mww 0x400d801c 0" \
  -c "mww 0x400d8000 0x80000000" -c "exit"
```

とすれば再起動する。`Failed to write memory at 0x00000000` が出るが、
これは再起動で DP が落ちた後の後片付けが失敗しているだけで、再起動自体は
成功している。

### 再起動が `/lib` の書き出しに割り込んだ

上の手動再起動は、直前の起動がまだ `/lib` を書いている最中に走った。
次の起動が

```
[R2P2] system file install hung last boot; skipping
```

を出して素通りし、その次の起動で全部入れ直した。ガードは働いたが、
[flashing-from-wsl.md](flashing-from-wsl.md) の「書き込みの直後に SWD で
フラッシュを触らない」がそのまま起きた形。**書き込み後は UART の
`installed /etc/picorubykaigi01-files` が出るまで SWD を触らない。**

## 次

- R2P2 のコンソールを UART にも出す。USB が直るまでの間、シェルに触る
  手段がこれしかない。`machine.c` の書き込み経路に UART 出力を足し、
  UART0 の受信割り込みで `picorb_hal_stdin_push` を呼ぶ
- UART0 は GROVE-B の `Board#grove_uart` と衝突する。コンソールを UART0 に
  置いたビルドではハード UART 版の GROVE-B は使えない（PIO 版は無事）
- halt が効かない原因
