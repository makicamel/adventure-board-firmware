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

## UART コンソール（`R2P2_CONSOLE_UART=1`）

USB が直るまでシェルに触る手段がこれしかないので、コンソールを UART にも
出すようにした（[upstream-changes.md](../upstream-changes.md) の 7）。
`picorb_hal_write` が CDC に加えて UART0 にも書き、UART0 の受信割り込みが
`picorb_hal_stdin_push` に流す。入力は CDC と同じリングバッファに入るので
Ctrl-C も cooked モードも同じに振る舞う。

```console
R2P2_CONSOLE_UART=1 rake docker:r2p2:picoruby:pico2:debug
rake docker:flash:picoruby:pico2:debug
R2P2_PORT=/dev/ttyACM0 tools/r2p2dev.py run 'ls /lib' 'free'
```

実機で確認できたこと:

- 起動ログに続いて `Starting shell...` とプロンプト `$> ` が UART に出る
- `r2p2dev.py run` で `ls` / `free` が往復する。`R2P2_PORT` を指定すると
  usbipd の付け外しや `/dev/serial/by-id` の探索を全部飛ばす
- Ctrl-C が効く（`^C` のエコーの後にプロンプトが戻る）
- `r2p2dev.py reset`（halt を `catch` で包んだ版）で再起動し、
  約 15 秒でプロンプトまで戻る

**UART0 は GROVE-B の `Board#grove_uart` と衝突する。** このビルドでは
ハード UART 版の GROVE-B は使えない（PIO の `grove_link` は無事）。

### Debug Probe が USB ごと固まる

`reset` の直後に `run` を続けると、2 回とも **プローブの USB が死んだ**。
症状は、tty への書き込みは通るが応答が無く、`close()` が返らない。
`dmesg` に `vhci_hcd: urb->status -104` が並び、Windows の `usbipd list` で
プローブが「不明な USB デバイス（デバイス記述子要求の失敗）」になる。
**usbipd の detach / attach では戻らず、物理的に抜き差しするしかない。**

`reset` → 25 秒生読み → `run` の順なら問題なかったので、ターゲットの再起動中に
ホストが送信する（`sync` の Ctrl-C と CR）ことが引き金に見えるが、原因は
プローブのファーム（2.0.0）側にあるはずで未解明。当面は
**`reset` のあと起動ログが流れ終わるまで `run` しない。**
debugprobe のファーム更新も試す価値がある。

## LED マトリクスの実チップ

`one_dot.rb` が `I2C write failed (IOError)` で落ちたところから、スクリプトを
`push` して 1 トランザクションずつ結果を見ていった。分かったこと:

- 0x34 / 0x35 とも ACK する。配線・アドレス・SDB は設計どおり
- **LGC を 0→1 にする config 書き込みの直後の 1 トランザクションが必ず落ちる。**
  SSD の遷移は無関係、20ms 空けても同じ、データシートに記載なし。
  落ちたのが書き込みだと、以後しばらく読み出しが 1 トランザクション遅れて返る。
  落ちたのが読み出しなら以後は正常
- gem の `configure` で LGC を立てた直後に捨て読みを 1 回入れて吸収した
  （[picoruby-is31fl3729/README.md](../../mrbgems/picoruby-is31fl3729/README.md)）。
  `one_dot.rb` と `frame.rb` がエラーなしで完走する

## 次

- halt が効かない原因
- Debug Probe が固まる条件の特定（ファーム更新で消えるか）
- `flash.sh` の再起動をトリガ書き込みまで `catch` で包んだ版は未検証
  （前の版はトリガ書き込みのエラーで 3 回リトライし、3 回再起動していた）
