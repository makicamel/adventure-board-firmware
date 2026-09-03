# WSL から RP2350 のボードを焼いて、デバッグする

Pico 2 W に R2P2 を焼いて実機で試すまでに踏んだ穴。**この repo に限らず、
WSL2 + Docker + PicoProbe で RP2040/RP2350 を触るなら同じところで詰まる**ので、
道具の実装ではなく「なぜそうしないといけないか」を残す。

道具そのものは [tooling.md](tooling.md)。

## USB を WSL に渡す

Windows のデバイスは usbipd-win で WSL に渡す。

```console
usbipd.exe list
usbipd.exe attach --wsl --busid 7-4
```

**`usbipd.exe` は WSL の中から直接呼べる**（`/mnt/c/Program Files/usbipd-win/`）。
PowerShell を開き直す必要はない。ただし `bind` は管理者権限が要るので、
初回だけ UAC を出す:

```console
powershell.exe -NoProfile -Command \
  "Start-Process -FilePath 'C:\Program Files\usbipd-win\usbipd.exe' \
   -ArgumentList 'bind','--busid','7-4' -Verb RunAs -Wait"
```

### アタッチはリセットのたびに落ちる

**ターゲットがリセットすると USB が再列挙し、usbipd のアタッチが切れる。**
そして書き込みはリセットする。プローブとボードの両方が落ちるので、
焼くたびに 2 つ繋ぎ直すことになる。自動化する価値がある。

**PID が変わると永続バインドも効かない。** ファームを入れ替えて USB ディスクリプタが
変わると（例: シリアル 1 本 + マスストレージ → シリアル 3 本）、
`Not shared` に戻って `bind` からやり直しになる。

**再列挙の直後、数秒間 `usbipd list` から消える。** すぐ `attach` すると
「そんなデバイスはない」と言われる。待つこと。

### tty の番号は動く

R2P2 は CDC を 3 本出す。プローブの UART と合わせて 4〜5 本の `/dev/ttyACM*` が
並び、**番号は列挙順で入れ替わる**。番号で掴んではいけない。

```console
ls /dev/serial/by-id/
usb-PicoRuby_R2P2_4385B28F5C8C9BA4-if00 -> ../../ttyACM2   # シェル
usb-PicoRuby_R2P2_4385B28F5C8C9BA4-if02 -> ../../ttyACM3
usb-PicoRuby_R2P2_4385B28F5C8C9BA4-if04 -> ../../ttyACM4
usb-Raspberry_Pi_Debug_Probe__CMSIS-DAP__...-if01 -> ../../ttyACM1
```

**再起動直後の by-id リンクは、まだ消えたノードを指している。** open は成功して
最初の write が `EIO` で返る。プロンプトが返ってくることを確認するまで、
掴めたと思ってはいけない。

## `stty` を使わない

`stty -F /dev/ttyACM2 raw -echo` は**ポートを自分で開く**。ボードが固まっていると
キャリア待ちでブロックしたまま帰ってこず、`timeout` の SIGTERM でも死なない
（tty の open は割り込み不可）。

`O_NONBLOCK` で開いて termios を直接設定する。`CLOCAL` を立てるのも同じ理由。

```python
fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
a = termios.tcgetattr(fd)
a[0] = a[1] = a[3] = 0
a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
a[4] = a[5] = termios.B115200
a[6][termios.VMIN] = a[6][termios.VTIME] = 0
termios.tcsetattr(fd, termios.TCSANOW, a)
```

ノンブロッキングなので**書き込みが `EAGAIN` で返る**。ボードが忙しいと
CDC を捌かなくなるので、`select` で待って書き切ること。
**書き込みがタイムアウトする＝ボードが固まっている**、という良い指標にもなる。

## openocd の `reset` を使わない

`reset run` はコアを **SYSRESETREQ** で落とすだけで、**ペリフェラルは残る**。
USB が生きたままファームが起動しなおすと、中途半端なデバイスを相手にして
プロンプトまで来ない。

**無言になったボードは、毎回この直後だった。** そして一度そうなると SWD から
メモリが 1 ワードも読めなくなり（コアの examine は通るのに `mdw` が無反応）、
BOOTSEL 以外に戻す手段がなくなる。

**書き込みの最後の `reset` も同じ。** `program ... verify reset exit` の
`reset` がこれなので、焼くたびに賭けをしていることになる。
`docker/flash.sh` は `verify exit` で止めて、別セッションでウォッチドッグを叩く。

デバイス側の `watchdog_reboot()` と同じ手順を SWD 越しに踏めばよい:

```
mww 0x40018008 0x01fffff3   # PSM_WDSEL: 発振器以外を全部リセット対象に
mww 0x400d801c 0            # WATCHDOG_SCRATCH4: 通常のブート経路へ
mww 0x400d8000 0x80000000   # WATCHDOG_CTRL: TRIGGER
```

RP2040 なら `PSM_BASE 0x40010000` / `WATCHDOG_BASE 0x40058000`、
`PSM_WDSEL_BITS & ~(ROSC|XOSC)` = `0x0001fffc`。
RP2350 は `0x40018000` / `0x400d8000`、`0x01fffff3`。

## 書き込みの直後に SWD でフラッシュを触らない

焼いた直後のボードはまだ起動中で、**ファーム自身がフラッシュに書いている**
（このファームは `/lib` とサンプルを起動時に書き出す）。その最中に SWD から
`reset init` して消しにいくと、書きかけのファイルシステムが残る。

一度、それで USB が
`0000:0002 不明な USB デバイス (デバイス記述子要求の失敗)` になった。
SWD は生きていたので `watchdog_reboot` 相当で復帰できたが、
**運が悪ければ BOOTSEL 行き**だった。

sleep で凌がないこと。**シェルのプロンプトが返るまで待つ**のが唯一の確証で、
それは「起動が終わってファームがフラッシュから手を離した」ことを意味する。

```python
def settle(timeout=25.0):
    while ...:
        con = Console(console_path())
        if con.sync(timeout=4.0):
            return True
```

同じ理屈で、**フラッシュ操作の直後に同じ openocd セッションでメモリを書かない**。
`flash erase_address` のあとにウォッチドッグを叩こうとすると
`Failed to write memory at 0x00000000` になる。セッションを分ける。

そして**消したあとの最初の起動は長い**。littlefs のフォーマット（512KB の消去）に
続けてファイルを全部書くので、プロンプトが返るまで数十秒かかることがある。
黙っているからといって、そこで畳みかけないこと。

## 戻せなくなったら BOOTSEL + picotool

コアが `Examination failed` になったり、`pc: 00000000 / BOOT ROM not found` に
なったら SWD では何もできない。**ROM のブートローダは必ず答える。**

BOOTSEL を押しながら USB を挿すと `2e8a:000f RP2350 Boot` で現れる。
そこからは picotool で全部やれる:

```console
picotool flash erase --all           # ファイルシステムごと消える
picotool flash load -x firmware.uf2  # 焼いて即実行
```

**picotool は Docker コンテナからでも使える**（USB デバイスと
`device_cgroup_rules: ["c 189:* rmw"]` を渡す）。ホストに何も入れなくてよい。

ファイルシステムだけ消したいなら、ボードが生きているうちに openocd で:

```
flash erase_address 0x10380000 0x00080000
```

（RP2350 の littlefs は `picoruby-littlefs/ports/rp2040/flash_hal.c` の
`LFS_FLASH_TARGET_OFFSET 0x00380000` から 512KB。
`cmake/CMakeLists.txt` の `FLASH_TARGET_OFFSET=0x00340000` は別用途なので
間違えないこと）

## ファームウェアが黙って死ぬ場所

### `bkpt` を無条件で置かない

R2P2 の `ports/rp2040/fault_handler.c` は、レジスタを printf したあとこうしていた:

```c
while (1) {
  __asm volatile("bkpt #0");
}
```

**`bkpt` はデバッガが halt しているときだけ止まる命令**で、繋がっていなければ
フォールトにエスカレートする。すでに HardFault の中なので **double fault**、
そしてロックアップ。SWD からメモリも読めなくなり、電源を抜くしかなくなる。

`DHCSR.C_DEBUGEN`（`0xe000edf0` bit 0）を見て、**デバッガが居るときだけ止まる**。
居なければ `watchdog_reboot()` する。

ついでに、ハンドラ冒頭で MSP を積み直しておく。**スタック溢れはフォールトの
主要な原因**で、そのままではハンドラ自身が自分のフレームを積めずにまた落ちる:

```
"LDR r3, =0xd0000000\n"   /* SIO CPUID */
"LDR r3, [r3]\n"
"CBZ r3, 1f\n"
"LDR r3, =__StackOneTop\n"
"B 2f\n"
"1:\n"
"LDR r3, =__StackTop\n"
"2:\n"
"MSR msp, r3\n"
```

### prod ビルドには stdio が無い

R2P2 の prod は `pico_enable_stdio_usb(0)` かつ `pico_enable_stdio_uart(0)`。
**`printf` はどこにも出ない。** 上のフォールトハンドラのレジスタダンプも、
自分で足したデバッグ出力も、全部消える。

デバッグ出力に頼る設計にしないこと。debug ビルドなら UART に出る。

### USB より前に危ないことをしない

ファイルシステムを触る処理を `main()` の USB 初期化より前に置くと、
**そこで止まったボードは何にも答えない**。コンソールも SWD も効かず、
BOOTSEL しかない。

littlefs はディレクトリを連結リストで辿るので、書きかけで落ちたファイルが
tail ポインタを壊せば `lfs_stat` は返らない。**壊れたファイルシステムが
ボードを殺す。**

どうしてもそこでやるなら、ウォッチドッグで囲って、次の起動で「前回やりかけた」と
分かったら丸ごと諦めること:

```c
watchdog_hw->scratch[0] = INSTALL_IN_PROGRESS;
watchdog_enable(8000, 0);
  ... mount / stat / mkdir / write ...
watchdog_disable();
watchdog_hw->scratch[0] = 0;
```

（`scratch[4..7]` は `watchdog_reboot()` が使うので避ける）

## ビルド成果物の取り違え

イメージ名にコミットハッシュを入れていると、ビルドディレクトリには
**ビルドしたコミットの数だけ**成果物が溜まる。それを全部 `dist/` にコピーすると
**全ファイルの mtime が同じになり**、`ls -t` で選ぶ「最新」がシェルの気分次第になる。

先週のファームを焼いて、直したはずの修正が効かないと悩む種になる。
**publish するのは今ビルドした 1 組だけにする。**

## 対話コンソールを自動で叩く

R2P2 のシェルは全画面の行編集をする。キーを 1 つ送るたびに**プロンプト行を
丸ごと描き直す**ので、素直に読むとこうなる:

```
[?25l[1G$> l[0K[0J[1F[1B[4C[?25h[?25l[1G$> ls[0K...
```

- ANSI を剥がしたうえで、**コマンド全体のエコーを見つけて、その後ろだけ**を返す
- プロンプト検出は**エコーが出揃ってから**にする。描き直しの途中で
  文字列末尾が `$> ` になる瞬間があり、そこで打ち切ると出力を取りこぼす
- 出力に `free` のようなコマンド名が現れると、素朴な `rfind(cmd)` が誤爆する。
  `"> " + cmd + "\n"` のように**プロンプトに固定して**探す

そして自明だが踏んだ罠: **道具が自分で表示する `$> ...` を、ボードの応答だと
思い込まないこと。** 出力が空なら、それはボードが黙っているということ。
