# `tools/r2p2dev.py`

WSL から実機の R2P2 を触るコマンド。**なぜこれが要るのか**は
[flashing-from-wsl.md](flashing-from-wsl.md) にある。ここは使い方。

```console
tools/r2p2dev.py attach                     # プローブとボードを WSL のバスに載せる
tools/r2p2dev.py port                       # コンソールの tty を出す
tools/r2p2dev.py run 'ls /lib' 'free'       # シェルに流して結果だけ返す
tools/r2p2dev.py push local.rb /home/t.rb   # ファイルを送る（小さいものだけ）
tools/r2p2dev.py reset                      # ウォッチドッグで再起動して繋ぎ直す
tools/r2p2dev.py wipefs                     # ファイルシステムを消して再起動
tools/r2p2dev.py recover                    # BOOTSEL から全消し＋焼き直し
```

すべて最初にアタッチし直すので、焼いた直後にそのまま続けられる。

## `run` — シェルに流す

行編集のエコーを剥がして、コマンドの出力だけを返す。

**表示される `$> ...` は道具が出している行で、ボードの応答ではない。**
出力が空なら、それはボードが黙っているということ。

## `push` — 小さいファイルだけ

irb 越しに `File#write` を並べる。**irb は最大連続 32KB しか持っていない**ので、
少し長い行で `NoMemoryError` になり、**書きかけのファイルを開いたまま落ちる**。
littlefs に中途半端な状態が残り、最悪ボードが起動しなくなる。

大きいものはファームに載せて運ぶこと。git 管理外の `devtest/` を
`tools/gen_system_files.rb` が拾って `/home/devtest/` に置く。
焼き直しに数分かかるが、デバイス上に一切書かない。

## `wipefs` — ライブラリを直したら

ファームは**変わったファイルだけ**書く（`/etc/picorubykaigi01-files` に
中身のハッシュを置いて比べる）。サンプルは一度置いたら二度と触らないので、
`sim/examples/` を直しても既存のボードには届かない。開発中は `wipefs` で
ファイルシステムごと消してから焼く。

## `recover` — 戻せなくなったら

コアが `Examination failed` になったり `pc: 00000000` になったら SWD では
何もできない。BOOTSEL を押しながら USB を挿してから、これを実行する。
`picotool` でフラッシュを全消しして、`dist/` の最新イメージを書き込む。

## MCP にするかどうか

まだ CLI のまま。実機で使い倒してコマンドが固まってからの方が早い。
