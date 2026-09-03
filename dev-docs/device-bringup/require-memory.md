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

## 原因 — `require` 1 回が 22KB を持っていって返さない

きれいなボード（フラッシュ全消し → ファーム書き込み）で、部品を 1 つずつ
require したときのヒープ:

| | used | free | max_free | frag |
|---|---:|---:|---:|---:|
| スクリプト開始 | 334,440 | 70,688 | 38,152 | 23 |
| `status_led`（**764 バイト**）| 356,800 | 48,328 | 20,416 | 55 |
| `speaker`（2,030 バイト）| **404,184** | **944** | 616 | 3 |

**764 バイトのファイル 1 本で 22KB。** そして返ってこない。
2 本目でヒープが尽きる。ファイルの大きさとほぼ無関係で、
**`require` そのものの固定費**である。

`Kernel#load_file`（`mrbgems/picoruby-require/mrblib/require.rb`）:

```ruby
sandbox = Sandbox.new('require')
begin
  sandbox.load_file(path)
  err = sandbox.error and raise err
  $LOADED_FEATURES << name_with_ext unless required?(name_with_ext)
ensure
  sandbox.terminate
end
```

`Sandbox.new` は `mrc_ccontext_new`（Prism のコンパイラ文脈）と irep と
タスクを作る。`Sandbox#load_file` はさらに `@code = rb` でファイル全体の
String を保持する（`exec_mrb` がポインタしか持たないため意図的）。
`terminate` はタスクを止めるだけで、`SandboxState` が解放されるのは
Sandbox オブジェクトが GC されたとき。

**GC が走らなければ、require するたびに 22KB ずつ失われる。**

これなら全部説明がつく:

- 15KB を 1 枚で require しても、5 枚に分けても、同じように落ちる
- 1 行の `/lib/tiny.rb` は通る（1 回分の 22KB は払える）
- 最大連続 93KB が空いていても 2 本目で尽きる

### GC を走らせれば戻る（実測）

```
開始           used 317,408   free 87,720
require 後     used 346,184   free 58,944    (+28,776)
GC.start 後    used 309,264   free 95,864    ← 開始より低い
```

**リークではない。誰も回収していないだけ。**
（`max_free` は 37,680 のまま戻らないので、断片化は残る）

直し方は `picoruby-require/mrblib/require.rb` の `load_file` で、
Sandbox を手放してから GC を促すこと。`ensure` の中では `sandbox` という
ローカルがまだ生きているので、そこで `GC.start` を呼んでも回収されない。

## 分割してみた結果 — サイズの問題ではなかった

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

つまり**サイズの問題ではない**（上の「原因」を参照）。分割自体は残す価値がある
——`require` は `Sandbox` をファイルごとに作るので、1 回あたりの上限は下がる
——が、固定費が 22KB では枚数を増やすほど不利になる。**分割はむしろ逆効果**
だった可能性がある。

### ファイルからの require そのものは通る

`/lib/tiny.rb` に `TINY = 1` の 1 行だけ置いて:

```
irb> require "tiny"
=> true
irb> TINY
=> 1
```

**通る。** サイズでも経路でもない。落ちるのはうちのライブラリの中身に依存している。

### もう一つ、別の壊れ方がある

`require` を 5 つ続けて流したあと、ボードが**無言**になった。
USB は列挙したままなのに、コンソールが一切返さない。

これは再起動した姿ではない（再起動ならシェルが返る）。
**VM が止まったまま TinyUSB だけ生きている**姿。

`Sandbox#load_file` は `join: true` なら `wait(timeout: nil)` に入り、
`while self.state != :DORMANT && self.state != :SUSPENDED` で回り続ける。
子タスクが異常終了したときにこの状態にならなければ、**シェルは永久に回る**。
NoMemoryError で戻ってきたケースとは別の壊れ方で、こちらはハードフォールトですらない。

つまり問題は 2 つある:

1. うちのライブラリを require すると NoMemoryError になる
2. 入れ子の sandbox で require が失敗したとき、シェルが返ってこないことがある

### 邪魔になっているもの

切り分けのたびにボードがロックアップし、**USB の抜き差しが要る**。
`ports/rp2040/fault_handler.c` の `HardFault_Handler` は printf でレジスタを
出そうとするが、prod は stdio が無効なので何も出ないうえ、スタックが溢れた
状態でハンドラ自身が落ちて double fault になる。

原因は `printf` ではなく、その先だった:

```c
  while (1) {
    __asm volatile("bkpt #0");
  }
```

**`bkpt` はデバッガが halt しているときだけ止まる命令**で、繋がっていなければ
フォールトにエスカレートする。すでに HardFault の中なので double fault、
そしてロックアップ。しかも prod は stdio が無効なので、その上で延々と出している
レジスタダンプは**どこにも出ていない**。生き延びる理由が何もない場所で
永久に止まっていた。

直した（`fault_handler.c`、2026-09-02）:

- naked ハンドラの冒頭で SIO CPUID を見て `__StackTop` / `__StackOneTop` に
  MSP を積み直す。スタックが溢れて来た場合でもハンドラ自身が動ける
- 末尾は `DHCSR.C_DEBUGEN` を見て、**デバッガが居るときだけ `bkpt`**。
  居なければ `stdio_flush()` して `watchdog_reboot(0, 0, 0)`

ウォッチドッグを使うのはペリフェラルごとリセットされて USB が自分で
再列挙するから。SYSRESETREQ はコアしか戻さない。

**ただしこれで全部が救われるわけではない。** 上の「無言になる」壊れ方は
フォールトではなく無限ループなので、フォールトハンドラは呼ばれない。

## USB が上がる前にファイルシステムを触るのは危ない

`picorb_install_system_files()` は `main()` の中で **USB より前**に走る。
そこで止まると、コンソールも SWD も効かず、**BOOTSEL 以外に戻す手段がない**。

実際に踏んだ:

- `push` が irb のメモリ切れで死に、littlefs のファイルを開いたまま落ちた
- 以後、焼き直して `Verified OK` になってもコンソールが無言、USB も再列挙しない
- openocd は**コア1 だけ examine に成功し、コア0 は応答しない**

littlefs はディレクトリを連結リストで辿るので、tail ポインタが壊れれば循環する。
`lfs_stat` が返らなければ、そこで永久に止まる。

**学習者は私より雑にファイルシステムを壊す。** ボードが二度と起動しなくなるのは
配布物として論外なので、囲った（2026-09-02）:

```c
watchdog_hw->scratch[0] = INSTALL_IN_PROGRESS;
watchdog_enable(8000, 0);
  ... mount / stat / mkdir / write ...
watchdog_disable();
watchdog_hw->scratch[0] = 0;
```

次の起動で `watchdog_caused_reboot()` かつ scratch[0] にフラグが残っていれば、
**インストールを丸ごと諦めてシェルまで進む**。サンプルが無い起動は不便なだけだが、
起動しないボードは死んだボード。

## GC を挟んでも足りない — 断片化と、そもそもの大きさ

`require` の前後で `GC.start` を挟んで 5 本を順に読ませた:

| | used | free | **max_free** | frag |
|---|---:|---:|---:|---:|
| `status_led` | 312,512 | 92,616 | 27,712 | 131 |
| `speaker` | 324,744 | 80,384 | 27,712 | 167 |
| `buttons` | 339,896 | 65,232 | **9,808** | 203 |
| `led_matrix` | **FAIL** | | | |

1 本 → 3 本まで伸びたが、4 本目で折れる。
**free は 65KB あるのに最大連続が 9.8KB。** 効いているのは断片化。

分割が逆効果だったのかを確かめるため、1 枚（14,817 バイト）でも試した:

```
{used: 322104, free: 83024, max_free: 78472, frag: 9}

NoMemoryError (NoMemoryError)
```

**連続 78KB あっても通らない。** 分割の是非以前の問題だった。

### 見積もり

実測から:

| | |
|---|---|
| コンパイルに要る**連続**領域 | ソースのおよそ **6 倍**（4.66KB は連続 27KB で通る／14.8KB は連続 78KB で落ちる） |
| 読み込んだあとの**常駐**コスト | ソースのおよそ **5 倍**（speaker 2.0KB → +12.2KB、buttons 2.7KB → +15.2KB） |
| `require` 1 回の**固定費** | 約 28KB（GC で戻る） |

ヒープは 396KB で、**シェルが起動しただけで 290KB 使っている**。
残り 100KB でこの倍率では、14.8KB のライブラリは入らない。

### つまり

**このライブラリは、今の R2P2 のビルド構成では、デバイス上でコンパイルできない。**
分割しても、GC を足しても、1 枚に戻しても足りない。

効きそうな順:

1. **基板用の build_config を痩せさせる。** 今の pico2_w 用は `networking` /
   `picoruby-ble` / `picoruby-ble-uart` / `picoruby-keyboard` / `USE_WIFI` を
   積んでいる。LED・音・ボタンの学習用基板には要らない。
   ベースラインの 290KB が下がれば、倍率はそのままでも入る
2. **`require` に GC を足す**（必要だが単独では足りない）
3. **サンプルは要る部品だけ require する。** LED のサンプルなら
   `board` と `led_matrix` の 2 本。今日の実機でも通る
4. **ライブラリ自体を削る**

## 直した結果（2026-09-03）

### 1. ビルド構成を痩せさせた

`build_config/r2p2-picoruby-pico2_w.rb` から `networking` gembox、
`picoruby-ble`、`picoruby-ble-uart`、`picoruby-keyboard` を外した。
LED・音・ボタン・GROVE の学習用基板には要らない。

| 起動直後 | used | free | **max_free** | T_PROC |
|---|---:|---:|---:|---:|
| 従来 | 290,880 | 114,248 | 80,072 | 1,996 |
| 痩せた版 | **220,608** | **184,520** | **160,912** | **1,423** |

**70KB 空き、最大連続が倍。** これだけで `require 'picorubykaigi01'` が通るようになった
（5 本全部読んで `free 98,776 / max_free 41,208` が残る。GC を挟んだ場合）。

`USE_WIFI` はまだ外していない。`tasks/picoruby/r2p2.rake` がボード名で
`-D USE_WIFI=1` を決め打ちしているため、基板用のボード名を足すときに一緒に外す。

### 2. 使うときに初めて読む

`require 'picorubykaigi01'` はローダと `Board` だけを読み、
ペリフェラルは**最初に触られたとき**にクラスごと require する。
ステータス LED を光らせるだけのプログラムが LED マトリクスをコンパイルしない。

`Board.load_part` は require のあとに `GC.start` を呼ぶ。upstream の
`require.rb` には触らずに、28KB の置き土産をその場で回収する。

実機（Pico 2 W、LED ドライバなし）:

```
require 'picorubykaigi01'   used 296,152 → 300,584   (+4,432)
board.status_led → true     used 280,368   ← GC で開始時より下がる
buttons.pressed?(:a)        used 301,928
speaker → Speaker           used 321,272   free 83,856
```

**LED マトリクスは一度も読まれないので、チップの無いボードでも I2C エラーが出ない。**
`/home/examples/status_led.rb` がそのまま走る。

## 実機で試すときの作法（痛い目を見て決めた）

- **irb でファイルを書かない。** `tools/r2p2dev.py push` は irb 越しに
  `File#write` を並べるが、irb は最大連続 32KB しかなく、少し長い行で
  NoMemoryError になる。**書きかけのファイルを開いたまま落ちる**ので、
  littlefs に中途半端な状態が残る
- **テスト用スクリプトはファームに載せて運ぶ。** git 管理外の `devtest/` を
  `tools/gen_system_files.rb` が拾って `/home/devtest/` に置く。
  焼き直しに 4 分かかるが、デバイス上に一切書かないので確実
- `$> ...` の行は `r2p2dev.py` が自分で表示している。**ボードの応答ではない。**
  出力が空なら、それはボードが黙っているということ
- **ライブラリを直して焼き直しても、デバイス上は古いまま。** インストーラは
  「無ければ書く」だけなので、既にあるファイルは触らない。
  `tools/r2p2dev.py wipefs` でファイルシステムを消してから焼く

## 残る宿題

学習用の基板で、`require` 一発で抜き差しするまで戻らないのは危ない。
分割で当面は避けられるが、**コンパイル時のメモリ／スタック不足が
そのままハードフォールトになる**という根っこは残っている。
