# Debug Probe だけで基板を触る — 手順書

USB の使えない r1 で、J2 に挿した Debug Probe（PicoProbe）の SWD と UART だけで
焼く・見る・試す、を回したときの手順。今後も「USB が無い / 信用できない」状況の
標準手順として使う。背景と経緯は [r1-board.md](r1-board.md)。

## 1. 繋ぐ

J2（1×5、2.54mm、DNP なので自分で付ける）:

| J2 | 信号 | MCU | Probe 側 |
|---|---|---|---|
| 1 | GND | | GND（SWD と UART の両方） |
| 2 | SWCLK | pin24 | SWD の SC |
| 3 | SWDIO | pin25 | SWD の SD |
| 4 | UART_RX | GPIO1 | **Probe の TX** |
| 5 | UART_TX | GPIO0 | **Probe の RX** |

- ネット名は MCU 視点。UART は TX と RX を**交差**させる
- Debug Probe 付属の 3 ピン JST-SH は SWCLK / GND / SWDIO の並びで、J2 の
  GND / SWCLK / SWDIO とは順番が違う。ジャンパで組み替える
- 電源は基板の USB-C から。プローブは給電しない

## 2. WSL に渡す

```powershell
usbipd list                          # 2e8a:000c "CMSIS-DAP v2 Interface" を探す
usbipd attach --wsl --busid 1-5      # 挿すたびに 1 回
```

WSL 側で `/dev/ttyACM0`（`/dev/serial/by-id/usb-Raspberry_Pi_Debug_Probe_*-if01`）が
UART、`lsusb` に Debug Probe が見えれば SWD も使える。

## 3. 焼く

```console
R2P2_CONSOLE_UART=1 rake docker:r2p2:picoruby:pico2:debug   # シェルを UART にも出す
rake docker:flash:picoruby:pico2:debug                       # SWD で焼いてウォッチドッグで再起動
R2P2_PORT=/dev/ttyACM0 tools/r2p2dev.py watch 30             # 起動ログを眺める
```

- `R2P2_CONSOLE_UART=1` が無いと、R2P2 のシェルは USB CDC にしか出ない。
  debug ビルドの `printf`（起動ログ）だけは無くても UART に出る
- 焼いた直後は `/lib` と `/home/examples` の書き出しが走る。UART に
  `installed /etc/picorubykaigi01-files` か `Starting shell...` が出るまで
  **何も送らない**（§6）
- 背景でビルドしたら、焼く前に**ログを `rake aborted!` で grep する**。
  `dist/` には前回の ELF が残っていて、失敗に気付かず古いのを焼ける

## 4. 触る

`R2P2_PORT` を付けると `r2p2dev.py` は usbipd も by-id の探索もせず、その tty を使う。

```console
export R2P2_PORT=/dev/ttyACM0
tools/r2p2dev.py run 'ls /lib' 'free'                 # シェルにコマンドを流す
tools/r2p2dev.py run --wait 12 '/home/examples/one_dot.rb'
tools/r2p2dev.py push local.rb /home/devtest/x.rb     # ファイルを送る（dfucli 経由）
tools/r2p2dev.py reset                                # ウォッチドッグで再起動
tools/r2p2dev.py watch 20                             # 生の出力を眺めるだけ
```

- `run` の出力が `$> cmd` だけで空なら、ボードは無言（応答ではない）
- `push` は R2P2 標準の `dfucli` に載せている。**irb には流し込まない**
  （`def` や `do` を含む行で `NoMemoryError`、書きかけのファイルが残る）
- `--wait` は返事を待つ秒数。サンプルは `require` に数秒かかる

## 5. 切り分けの型

`one_dot.rb` の `I2C write failed` を LGC の 1 トランザクションまで追い詰めた
やり方。ハードの疑いがあるときはこの順で。

1. **配線を PCB から機械抽出**して思い込みを消す（`tmp/picorubykaigi01-board/*.kicad_pcb`
   をパースして pad → net の表にする。r1-board.md にスクリプトがある）
2. **短いスクリプトを `push` して 1 トランザクションずつ結果を出す。**
   `ok = ->(...) { begin ... "o" rescue "X" end }` で成否を 1 文字にすると、
   `ooX` / `oXoo` のように並べて比較できる
3. **書けたら読み戻す。** 「成功」と返った書き込みが本当に届いているかは
   読み戻すまで分からない（LGC の件では、失敗の次の「成功」が届いていなかった）
4. 変数を 1 つずつ動かす（周波数 / 遅延 / レジスタ / ビット）。
   時間を空けても変わらないなら、タイミングではなく状態の問題

## 6. 落とし穴（順に痛い）

- **`reset` や書き込みの直後にコンソールへ送らない。** 起動中に `sync`（Ctrl-C と
  CR）を送ると Debug Probe が USB ごと固まった（2 回）。症状: 書けるが返事が無い、
  `close()` が返らない、`dmesg` に `vhci_hcd: urb->status -104`、Windows で
  「不明な USB デバイス」。**抜き差しでしか戻らない**（usbipd の detach/attach では無理）
- **この基板では openocd の `halt` が効かない**（両コア `unknown`）。読み書きと
  `program` は通る。ウォッチドッグ再起動は `catch {halt}` で halt を飛ばして
  レジスタを直接書く（`flash.sh` / `r2p2dev.py` 対応済み）。gdb は当面使えない
- **`push` は 256 バイトごとに 150ms 空ける。** デバイスの stdin リングは 1KB で、
  受信ループがすぐには読まない。速く送ると 1023 バイト目以降が消える
- **ホストで `rake sim:test` を走らせた後のコンテナビルドが落ちる**ことがある
  （`build/host/src/version.pi` が無い）。`rm -rf build/host` で直る
- openocd の `Error: busy command USB transfer` / `late transfer competed` は
  usbip 経由の CMSIS-DAP でよく出るが、内部でリトライされて `Verified OK` まで通る
- 再起動直後の `Failed to write memory at 0x00000000` は、トリガ書き込みの途中で
  リセットが掛かった後片付けの失敗。再起動自体は成功している
- **`/lib` を書き直す起動のあとは、しばらく入力の文字が抜ける**（2026-09-27、prod）。ファームが `/lib` と
  サンプルをフラッシュに書いているあいだは CPU が止まるので、UART の受け取りが追いつかない。
  `r2p2dev.py run` の 1 文字 6ms だと 1 文字おきに落ち、`ls /lib` が `ls/lb: command not found` になった。
  書き終われば 6ms で通る（10〜30ms も同じ）。プロンプトが出ても書き込みが続いていることがあるので、
  文字が抜けたら少し待って打ち直す。既定の間隔を広げる必要は無い
- **`wipefs` が再起動の前で止まることがある。** 消去は最後の区画（`0x3e0000`〜`0x3fffff`）まで進んだのに、
  openocd の完了の報告（`erased`）が見つからず、失敗扱いで終わった。消去は済んでいるので、
  `r2p2dev.py reset` で再起動すれば、次の起動でファイルシステムが作り直される
- irb は使わない（§4）。どうしても対話するなら 1 行を短く、`def` を打たない
