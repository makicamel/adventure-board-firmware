# `require "picorubykaigi01"` が通らなかった

2026-09-02、Pico 2 W 実機。ファームに内蔵した `/lib/picorubykaigi01.rb` を
初めて実機で読もうとしたら落ちた。以下は計測の記録。

## 配置そのものは成功している

UF2 を焼いた直後の実機:

```console
$> ls /lib
picorubykaigi01.rb
$> ls /home/examples
buttons.rb  checker.rb  forgot_setup.rb  frame.rb  gradient.rb
grove_uart_chat.rb  kanji.rb  l_shape.rb  left_column.rb  melody.rb
one_dot.rb  scroll.rb  shapes.rb  sound_and_light.rb  spinner.rb  status_led.rb
```

**UF2 1 本で 17 ファイルすべてが入った。** `picorb_install_system_files()` の
設計は意図どおり動いている。焼き直してもファイルは消えない（UF2 は
0x10000000〜0x10245900、littlefs は 0x10380000 から。1.2MB 離れている）。

## 落ち方

```
irb> require "picorubykaigi01"
NoMemoryError (NoMemoryError)
```

2 回目以降は例外にすらならず、**両コアが double fault でロックアップ**する。

```
Error: [rp2350.dap.core0] clearing lockup after double fault
Error: [rp2350.dap.core1] clearing lockup after double fault
```

この状態からは SWD で戻せない。`reset run` の直後にまたロックアップし、
最後は `pc: 00000000` / `BOOT ROM not found` まで行った。
**USB を抜き差しする以外に復帰手段がない。**

prod ビルドは `pico_enable_stdio_usb 0` / `pico_enable_stdio_uart 0` で
stdio が丸ごと無効なので、`ports/rp2040/fault_handler.c` の `printf` は
どこにも出ない。スタックが溢れた状態でハンドラ自身が再び落ちて double fault、
という筋が通る（prod の core0 スタックは 16KB）。

## メモリの実測

`free`（= `p PicoRubyVM.memory_statistics`）。単位はバイト。

| 状況 | used | free | **max_free** | frag |
|---|---:|---:|---:|---:|
| 起動直後のシェル | 290,632 | 114,496 | **93,264** | 13% |
| irb に入っただけ | 369,272 | 35,856 | **32,720** | 11% |
| シェルからスクリプト実行 | 309,360 | 95,768 | **47,496** | 23% |

ヒープは全体で 396KB（`HEAP_SIZE_KB 396`、RP2350 + WiFi + 共有アロケータ）。
**起動しただけでシェルが 290KB 使っている。**

効いているのは free ではなく **max_free（最大連続ブロック）**。
Prism の実行時コンパイルは連続領域を要る。

- irb 経由: 連続 **32KB** しかない。`f.methods.sort.inspect` すら NoMemoryError
- スクリプト経由: 連続 **47KB**。それでも 15KB のソースは通らない

## 原因

`lib/picorubykaigi01.rb` は **15,039 バイト / 560 行**（うちコード 367 行）。

R2P2 が標準で積んでいるスクリプトの最大は `sl.rb` の 8,382 バイト。
**うちのライブラリは標準の最大の 1.8 倍**で、1 回のコンパイル単位として大きすぎる。

内訳:

| 部分 | 行 | バイト |
|---|---|---:|
| ヘッダ | 1-13 | 585 |
| `Board` | 14-147 | 4,422 |
| `LedMatrix` | 154-297 | 3,639 |
| `Speaker` | 306-379 | 1,627 |
| `StatusLed` | 389-419 | 388 |
| `Buttons` | 432-534 | 2,102 |
| トップレベル | 535-561 | 633 |

## 対処

**クラスごとにファイルを分ける。** 1 回のコンパイル単位が最大 4.4KB になり、
標準の `sl.rb` の半分に収まる。ソースは `/lib` に置いたまま読めて直せる
（プリコンパイルはこの設計目標を壊すので採らない）。

検討して採らなかった案:

| 案 | 理由 |
|---|---|
| 本文を削る | コメント 7KB はコンパイル時メモリにほぼ効かない。効果が薄い |
| `.mrb` にプリコンパイル | 「ユーザが読んで直せる」という設計目標を壊す |
| core0 スタックを 16KB→24KB | ヒープを削る。NoMemoryError の方は直らない |

## 分割してみた結果 — 直らなかった

`lib/picorubykaigi01/` にクラスごとに分けた（最大 4.6KB、標準の `sl.rb` の
半分強）。`Kernel#require` は `load_file` でファイルごとに `Sandbox` を作って
`terminate` するので、コンパイル用のメモリはファイル間で解放される。狙いは
合っていたはずだった。

焼いてリセットし、シェルからスクリプトとして実行:

```
{allocator: :ESTALLOC, total: 405504, used: 302712, free: 102416, max_free: 93280, frag: 13}

NoMemoryError (NoMemoryError)
```

**最大連続 93KB が空いている状態で、1,819 バイトのローダが NoMemoryError。**
ローダの中の `require 'picorubykaigi01/board'`（4.6KB）まで含めても、
93KB を要求する処理はどこにもない。

つまり**サイズの問題ではない**。分割は無駄ではない（大きい 1 枚より確実に安全）が、
原因は別にある。

### 次に切り分けること

1. `/lib/tiny.rb` に 1 行だけ置いて `require "tiny"` — **ファイルからの require が
   そもそも通るのか**。R2P2 標準で `/lib` からファイルを require する経路は、
   探した限りどこも使っていない（`require 'editor'` などは組み込み gem を引く
   `extern` の方）。ここが通らなければサイズは無関係
2. 通るなら、部品を 1 つずつ require して落ちる場所を特定する

### 邪魔になっているもの

切り分けのたびにボードがロックアップし、**USB の抜き差しが要る**。
`ports/rp2040/fault_handler.c` の `HardFault_Handler` は printf でレジスタを
出そうとするが、prod は stdio が無効なので何も出ないうえ、スタックが溢れた
状態でハンドラ自身が落ちて double fault になる。

**フォールトしたら黙って再起動する**ようにすれば、抜き差しは要らなくなり、
配布したあとの学習者も助かる。upstream ファイルへの変更になるので、
これは相談してから。

## 残る宿題

学習用の基板で、`require` 一発で抜き差しするまで戻らないのは危ない。
分割で当面は避けられるが、**コンパイル時のメモリ／スタック不足が
そのままハードフォールトになる**という根っこは残っている。
