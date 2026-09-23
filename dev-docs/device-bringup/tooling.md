# `tools/r2p2dev.py`

WSL から実機の R2P2 を触るコマンド。**なぜこれが要るのか**は
[flashing-from-wsl.md](flashing-from-wsl.md) にある。ここは使い方。

```console
tools/r2p2dev.py attach                     # プローブとボードを WSL のバスに載せる
tools/r2p2dev.py port                       # コンソールの tty を出す
tools/r2p2dev.py run 'ls /lib' 'free'       # シェルに流して結果だけ返す
tools/r2p2dev.py push local.rb /home/t.rb   # ファイルを送る（小さいものだけ）
tools/r2p2dev.py reset                      # ウォッチドッグで再起動して繋ぎ直す
R2P2_PORT=/dev/ttyACM0 tools/r2p2dev.py run 'ls /lib'   # USB が無い基板: プローブの UART 経由
tools/r2p2dev.py watch 20                   # 生の出力を眺めるだけ（起動ログ用。何も送らない）
tools/r2p2dev.py wipefs                     # ファイルシステムを消して再起動
tools/r2p2dev.py recover                    # BOOTSEL から全消し＋焼き直し
```

すべて最初にアタッチし直すので、焼いた直後にそのまま続けられる。

`reset` と `wipefs` は、**ボードがプロンプトを返すまで待ってから**
SWD を叩く。焼いた直後のボードはまだ起動中で、ファーム自身が `/lib` と
サンプルをフラッシュに書いている。その最中に消しにいくと書きかけが残り、
一度は USB がディスクリプタを返さなくなった。

## `run` — シェルに流す

行編集のエコーを剥がして、コマンドの出力だけを返す。

**表示される `$> ...` は道具が出している行で、ボードの応答ではない。**
出力が空なら、それはボードが黙っているということ。

## `push` — R2P2 の `dfucli` で送る

シェル組み込みの `dfucli <path>` がコンソールを raw にして 19 バイトの DFU
ヘッダ + 本体を受け取るので、それに載せる。バイナリ安全で、素の R2P2 に何も足さない。
1KB ちょっとのスクリプトなら 1 秒。

以前は irb 越しに `File#write` を並べていたが、irb は `def` や `do` を含む行を
複数行の入力と見なして待ち続け、**その途中で `NoMemoryError`** になった。
書きかけのファイルを開いたまま落ちるので littlefs に中途半端な状態が残る。
irb に何かを流し込む用途にはもう使わない。

デバイス側の stdin リングバッファは 1KB で、受信ループがすぐには読まない。
256 バイトごとに 150ms 空けて送っている（40ms では 1023 バイト目以降が消えた）。
（`devtest/` をファームに焼き込んで `/home/devtest/` に置く仕組みは 2026-09-23 に廃止した。
`r2p2dev.py push` は PicoModem 経由で数十 KB でも送れる。）

## `wipefs` — ライブラリを直したら

ファームは**変わったファイルだけ**書く（`/etc/picorubykaigi01-files` に
中身のハッシュを置いて比べる）。サンプルは一度置いたら二度と触らないので、
`sim/examples/` を直しても既存のボードには届かない。開発中は `wipefs` で
ファイルシステムごと消してから焼く。

## `recover` — 戻せなくなったら

コアが `Examination failed` になったり `pc: 00000000` になったら SWD では
何もできない。BOOTSEL を押しながら USB を挿してから、これを実行する。
`picotool` でフラッシュを全消しして、`dist/` の最新イメージを書き込む。

## ブラウザのコンソールに渡す

R2P2 は WebSerial のコンソールを持っている（https://picoruby.org/terminal）。
Windows 側のブラウザから使うには、**WSL から外す**:

```console
usbipd.exe detach --busid 7-4
```

`usbipd list` が `Attached` から `Shared` に戻れば Windows のもの。
シェルは 1 本目の CDC（`-if00`）。戻すときは `tools/r2p2dev.py attach`。

## MCP にするかどうか

まだ CLI のまま。実機で使い倒してコマンドが固まってからの方が早い。
