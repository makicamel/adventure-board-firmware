# PicoRuby で `require` はいくらかかるか

`/lib` に置いたボードライブラリが実機で読めなかった。原因を追ったら
**PicoRuby でファイルを `require` することの費用**の話になったので、
その数字と、そこから決めた設計を残す。

計測は Raspberry Pi Pico 2 W、R2P2 4.0.3、prod ビルド、ヒープ 396KB。
値は `p PicoRubyVM.memory_statistics`（シェルの `free`）。

## 何が起きたか

```
irb> require "picorubykaigi01"
NoMemoryError (NoMemoryError)
```

15KB のソース 1 枚。最大連続 93KB が空いている状態で落ちる。
2 回目以降は例外にすらならず、ボードがロックアップした
（→ [flashing-from-wsl.md](flashing-from-wsl.md) の `bkpt` の話）。

## 費用の内訳

`Kernel#require` は `picoruby-require/mrblib/require.rb` でこうしている:

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
タスクを作る。`Sandbox#load_file` は `@code = rb` でファイル全体の String も
保持する（`exec_mrb` がポインタしか持たないので意図的）。
**`terminate` はタスクを止めるだけで、`SandboxState` が解放されるのは
Sandbox オブジェクトが GC されたとき。**

きれいなボードで、部品を 1 つずつ require したときのヒープ:

| | used | free | max_free | frag |
|---|---:|---:|---:|---:|
| 開始 | 334,440 | 70,688 | 38,152 | 23 |
| `status_led.rb`（**764 バイト**）| 356,800 | 48,328 | 20,416 | 55 |
| `speaker.rb`（2,030 バイト）| **404,184** | **944** | 616 | 3 |

**764 バイトのファイル 1 本で 22KB。** ファイルの大きさとほぼ無関係な固定費で、
2 本目でヒープが尽きる。

`GC.start` を挟むと戻る:

```
開始           used 317,408   free 87,720
require 後     used 346,184   free 58,944    (+28,776)
GC.start 後    used 309,264   free 95,864    ← 開始より低い
```

**リークではない。誰も回収していないだけ。**

## 三つの数字

実測から出した目安。

| | |
|---|---|
| `require` 1 回の固定費 | 約 **28KB**（GC で戻る） |
| コンパイルに要る**連続**領域 | ソースのおよそ **6 倍** |
| 読み込んだあとの**常駐** | ソースのおよそ **5 倍** |

連続領域の根拠: 4.66KB のファイルは最大連続 27KB で通り、
14.8KB のファイルは最大連続 78KB で落ちる。

常駐の根拠: `speaker.rb` 2.0KB → +12.2KB、`buttons.rb` 2.7KB → +15.2KB。

## 効かなかった対策

### ファイルを分ける

`require` はファイルごとに `Sandbox` を作って `terminate` するので、
分ければコンパイル用のメモリはファイル間で解放されるはず——という読みで、
15KB を 5 クラスに分けた（最大 4.6KB）。**直らなかった。**
1,819 バイトのローダが、最大連続 93KB が空いた状態で `NoMemoryError` を出す。

固定費 28KB が枚数ぶんかかるので、**分割はむしろ不利**だった。

### 1 枚に戻す

逆に 14,817 バイト 1 枚でも試した。最大連続 78KB あって通らない。
**分割の是非以前の問題だった。**

### GC を挟む

`require` のたびに `GC.start` すると 1 本 → 3 本まで伸びたが、4 本目で折れた:

| | used | free | **max_free** | frag |
|---|---:|---:|---:|---:|
| `status_led` | 312,512 | 92,616 | 27,712 | 131 |
| `speaker` | 324,744 | 80,384 | 27,712 | 167 |
| `buttons` | 339,896 | 65,232 | **9,808** | 203 |
| `led_matrix` | **FAIL** | | | |

**free は 65KB あるのに最大連続が 9.8KB。** 効いているのは断片化。
GC は必要だが、それだけでは足りない。

## 効いた対策

### 1. ビルド構成を痩せさせた

**シェルが起動しただけで 290KB 使っていた**（ヒープ 396KB）。
残り 100KB に上の倍率をかけると、14.8KB のライブラリはどう転んでも入らない。

`build_config/r2p2-picoruby-pico2_w.rb` から `networking` gembox、
`picoruby-ble`、`picoruby-ble-uart`、`picoruby-keyboard` を外した。
LED・音・ボタン・GROVE の学習用基板には要らない。

| 起動直後 | used | free | **max_free** | T_PROC |
|---|---:|---:|---:|---:|
| 従来 | 290,880 | 114,248 | 80,072 | 1,996 |
| 痩せた版 | **220,608** | **184,520** | **160,912** | **1,423** |

**70KB 空き、最大連続が倍。** これだけで `require 'picorubykaigi01'` が
5 本全部読めるようになった（GC 挟みで `free 98,776 / max_free 41,208` が残る）。

`USE_WIFI` はまだ外していない。`tasks/picoruby/r2p2.rake` がボード名で
`-D USE_WIFI=1` を決め打ちしているので、基板用のボード名を足すときに一緒に外す。

### 2. 使うときに初めて読む

`require 'picorubykaigi01'` はローダと `Board` だけを読む。
ペリフェラルのクラスは、**最初に触られたとき**に `Board.load_part` が
require する。ステータス LED を光らせるだけのプログラムが
LED マトリクスをコンパイルしない。

```ruby
def self.load_part(name)
  require "picorubykaigi01/#{name}"
  GC.start
rescue NameError, NoMethodError
  nil
end
```

`GC.start` はここで呼ぶ。`require.rb` の `ensure` の中では `sandbox` という
ローカルがまだ生きているので、そこで呼んでも回収されない。
**upstream に触らずに 28KB を回収できる場所がここだった。**

実機（Pico 2 W、LED ドライバなし）:

```
require 'picorubykaigi01'   used 296,152 → 300,584   (+4,432)
board.status_led → true     used 280,368   ← GC で開始時より下がる
buttons.pressed?(:a)        used 301,928
speaker → Speaker           used 321,272   free 83,856
```

**LED マトリクスを一度も読まないので、チップの無いボードでも I2C エラーが出ない。**
`/home/examples/status_led.rb` がそのまま走る。

## 残っている宿題

- **`require.rb` が GC を呼ばない**のは upstream の問題として残っている。
  `load_file` を抜けてから回収を促す必要があり、`ensure` の中では遅い
- **断片化**は estalloc の性質で、こちらから打てる手が少ない。
  読み込む数を減らすのが唯一効いた対策だった
- ボードライブラリはこれ以上大きくしにくい。機能を足すなら、
  **常駐がソースの 5 倍**であることを前提に置く場所を選ぶ
  （C の gem ならフラッシュに載ってヒープを食わない）

## この repo での置き場所

| | |
|---|---|
| ボードライブラリ | `lib/picorubykaigi01.rb` + `lib/picorubykaigi01/*.rb` → デバイスの `/lib` |
| 遅延読み込み | `Board.load_part` / `Board#matrix` などのアクセサ |
| ビルド構成 | `build_config/r2p2-picoruby-pico2_w.rb` |
| 配布 | `tools/gen_system_files.rb` → `picoruby-r2p2/ports/rp2040/system_files.c` |
