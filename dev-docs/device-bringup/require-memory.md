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

### 2. 使うものだけ読む

`require 'picorubykaigi01'` はローダと `Board`（ピンと起こし方）だけ。
**ペリフェラルのクラスはプログラムが自分で require する。**

```ruby
require 'picorubykaigi01'
require 'picorubykaigi01/led_matrix'
```

一度これを `Board` のアクセサに隠して、触られたときに require する形にした。
撤回した。**サンプルが何を読み込んでいるかは、サンプルが教えることの一部**で、
このデバイスではそれが実費でもある。隠す理由がない。

`Board` 側に残したのは**構築**の遅延だけ。LED マトリクスを使わないプログラムは
ドライバを開かず、SDB も上げない（全点灯＋音声で USB 500mA を超える基板なので、
使わないハードを起こさないことには実利がある）。

### 3. サンプルは 1 本読むごとに GC を呼ぶ

`require.rb` が回収しない以上、どこかで呼ぶしかない。**サンプルの中で呼ぶ。**
ライブラリの中に隠すと、ユーザは自分のプログラムで同じことをする必要に
気づけない。

```ruby
# require したファイルは、コンパイラをヒープに残していく。
# 1 本読むたびに GC で回収しないと、次が読めなくなる。
require 'picorubykaigi01'
GC.start
require 'picorubykaigi01/led_matrix'
GC.start
```

**呼ぶ場所が効く。** 同じファーム、同じ 4 本の require で測った最終状態:

| | used | free | **max_free** |
|---|---:|---:|---:|
| 呼ばない | 331,384 | 73,744 | **12,328** |
| 最後に 1 回 | 308,016 | 97,112 | **12,328** |
| **1 本ごと** | 320,448 | 84,680 | **20,736** |

最後にまとめて呼ぶと `used` は戻るが `max_free` は戻らない。
**1 本ごとに呼んで初めて断片化が抑えられ、最大連続が 68% 増える。**
効いているのは総量ではなく連続領域なので、この差が効く。

`GC.start` はブラウザの PicoRuby.wasm にも `bin/picoruby` にもある。
サンプルは 3 つの環境で同じコードのまま動く。

一番重いサンプル（`status_led.rb`、3 つ使う）を実機で測った:

| | used | free | max_free |
|---|---:|---:|---:|
| 開始 | 258,240 | 146,888 | 133,328 |
| `picorubykaigi01` | 297,288 | 107,840 | 25,800 |
| `led_matrix` | 339,216 | 65,912 | 21,328 |
| `buttons` | 307,888 | 97,240 | 11,280 |
| `status_led` | 329,992 | 75,136 | 11,280 |
| `board.status_led.on` | 331,432 | 73,696 | 11,280 |

通る。`GC.start` を最後に呼ぶと used は 308,064 まで戻るが、
**max_free は 11,280 のまま**——断片化は戻らない。

`melody.rb`（`speaker` だけ）も走る。`one_dot.rb` は `I2C write failed` で
落ちるが、これは LED ドライバの載っていない Pico 2 W なので正しい失敗。

## 残っている宿題

- **`require.rb` が GC を呼ばない。** upstream の仕様変更になるので触らない、
  という判断。サンプル側で `GC.start` を並べて凌いでいる。
  直すなら `load_file` を抜けてから回収を促す必要があり、`ensure` の中では
  `sandbox` ローカルがまだ生きているので遅い
- **断片化**は estalloc の性質で、こちらから打てる手が少ない。
  読み込む数を減らすのが唯一効いた対策だった
- ボードライブラリはこれ以上大きくしにくい。機能を足すなら、
  **常駐がソースの 5 倍**であることを前提に置く場所を選ぶ
  （C の gem ならフラッシュに載ってヒープを食わない）

## この repo での置き場所

| | |
|---|---|
| ボードライブラリ | `lib/picorubykaigi01.rb` + `lib/picorubykaigi01/*.rb` → デバイスの `/lib` |
| 構築の遅延 | `Board#matrix` などのアクセサ |
| サンプルが読むもの | 各 `examples/*.rb` の先頭 |
| ビルド構成 | `build_config/r2p2-picoruby-pico2_w.rb` |
| 配布 | `tools/gen_system_files.rb` → `picoruby-r2p2/ports/rp2040/system_files.c` |

## 入れ子の `require` と、使うときに読む形（2026-09-27、r1、prod）

サンプルの `require` を 1 行にしようとして、部品のファイル（`led_matrix.rb` など）の先頭で `require 'adventure_board'`
するようにしたら、実機で `NoMemoryError` が出るようになった。入れ子の `require` は、外のファイル（`led_matrix.rb`）の
コンパイル結果を持ったまま中のファイル（`board.rb`）をコンパイルするので、連続した空きが細切れになる。

どれもリセット直後から。値はバイト。

| 形 | リセット直後の `kanji.rb` | `kanji.rb` → `melody.rb` | 残った最大連続（max_free） |
|---|---|---|---|
| 入れ子（`require 'adventure_board/led_matrix'` の 1 行） | 3 回中 1 回 `NoMemoryError` | 2 回中 1 回 `NoMemoryError` | 7,048〜20,280 |
| 入れ子の直後に `GC.start` | `require` だけで `NoMemoryError` | — | 15,120 |
| 前の形（`require 'adventure_board'` → `GC.start` → `require 'adventure_board/led_matrix'` → `GC.start`） | 3 回とも成功 | 成功 | 約 27,000 |
| **使うときに読む**（`require 'adventure_board'` の 1 行。`AdventureBoard.matrix` が `led_matrix.rb` を読んで `GC.start`） | 成功 | 4 回とも成功 | 17,000〜24,000 |

採ったのは最後の形（`lib/adventure_board.rb` の `AdventureBoard.use`）。全 12 サンプルをリセット直後に 1 本ずつ走らせて、
`NoMemoryError` は出なかった。`melody.rb` のあとの空きは、前の形で約 57KB、この形で 58〜94KB。
