# 終わった Task はメモリに残る

短い効果音を `play_mml` で何度も鳴らすと、だんだんメモリが減って `NoMemoryError` で止まる。
makicamel さんが量産版 V1 の prod ビルドで見つけた（2026-10-27、PR #2）。
調べると、**タスクの仕組み（`mruby-task`）がそう作られている**ことが分かった。不具合ではない。

## 症状（PR #2 の測定）

`Task.new { x = 1 }` を 20 個ずつ作り、`GC.start` のあとで測る（V1、prod）。

| 作った Task | used | max_free |
|---|---|---|
| 20 | 240,800 | 158,360 |
| 40 | 267,648 | 136,880 |
| 80 | 320,712 | 83,736 |
| 140 | 400,568 | 3,760 → 次で `NoMemoryError` |

1 つ約 1.3KB。`play_mml("t150 o4 l16 c <g e c")` を 3 回鳴らすたびに約 9KB 減った。
Task のブロックが `Player` を掴んでいるので、Task だけでなく `Player` と曲のデータ（`Sequence`）も一緒に残るためだと思われる。

## 原因: 終わった Task は `close` するまで残る

`mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-task/` を読んだ結果:

- 走り終えた Task は捨てずに「休止中」（DORMANT）の一覧に移る。README にも
  「DORMANT: まだ始まっていない、または実行を終えたタスク」とあり、`Task.list` は休止中のものも返す
- 休止中の Task はもう一度使われることがある。`src/task.c` の `suspend_task_internal` に
  「PicoRuby の IRB は休止中のタスクを止めて再利用する」とある
- **GC では回収されない。** `src/task.c` の `task_unshare_envs` の上のコメントに
  「タスクは生きているあいだずっと GC に登録されたままで、GC が解放するのはヒープを片付けるときだけ」とある
- 解放するのは **`Task#close`**（`mrb_close_task`）。止めて（走っていても止める）、一覧から外し、スタックごとメモリを返す。
  自分自身（今走っている Task）は `close` できない（`can't close current task`）
- **README に `Task#close` の説明が無い**（`Task::Queue#close` しか無い）。気づきにくいのはこのため

なので本当の問題は、**`MIDIBASE::MML::Player#start` が曲ごとに Task を作り、誰も `close` しないこと**。
`Player` は Task を `@task` に入れているが、外から取り出すメソッドが無いので、使う側は `close` できない。

## 直し方の制約: ファームはもう量産基板に書いてある

2026-10-26 に量産基板へ `v2026.10.25` を書き込んだ。ファームに焼き込まれている `picoruby-midibase-mml`（`Player`）は直せない。
直すのは**あとから差し替えられるファイル**の範囲で行う。

`/lib` のファイルは差し替えられる。ファームは起動のたびに、自分が持っているファイル一式のハッシュと
`/etc/adventure-board-files` を比べ、同じなら何も書かない（`mrbgems/picoruby-r2p2/ports/rp2040/system_files.c`）。
基板の `/lib/adventure_board/speaker.rb` を上書きすると、次に別のファームを焼くまでそのまま使われる
（別のファームを焼くと、そのファームの版で書き直される）。
参加者の基板へ届ける手段として、コンソールに［ライブラリを最新にする］などを足す計画がある（[../webserial-console/file-transfer-plan.md](../webserial-console/file-transfer-plan.md)、未実装）。

## 直し方: `Speaker` が Task を自分で作り、曲を替えるときに `close` する

`lib/adventure_board/speaker.rb` だけを変える。

- `play_mml` は `Player#start` を呼ばず、`@task = Task.new(name: "Speaker") { player.run }` で自分で走らせる
  （`Player#start` の中身と同じ）
- `halt`（`play_mml` の頭と `stop` で呼ばれる）で、前の曲の `Player#stop` のあと `@task.close` する

これで、残る Task は多くても 1 つ（最後に鳴らし終えた曲）になる。PR #2 でこの形にした（2026-10-27）。

### 使い回す形をやめた理由

PR #2 は最初、最初の `play_mml` で Task を 1 つだけ作り、`Task::Queue` で `Player` を渡して使い回していた。
これでもメモリは減らないが、**シェルと組み合わせると音が出なくなる**場合がある。

1. スクリプト A が初めて `play_mml` を呼ぶ → 使い回す Task が A の実行中に作られる
2. A がエラーで終わる → シェルは A が作った Task を全部止める（`mrbgems/picoruby-shell/mrblib/job.rb` の `reap`）
3. `$board` は次のスクリプトにも残るので、B の `play_mml` は同じキューに曲を入れる。取り出す Task がもういないので、
   **エラーも出ずに音だけ出なくなる**（リセットするまで）

`close` の形は曲ごとに Task を作るので、この問題は起きない。シェルに止められた Task を後で `close` しても問題ない
（`close` は止まっている Task にも使える）。

止めるのは、スクリプトが**例外で終わったとき**だけ。Ctrl-C で止めたときと、ふつうに終わったときは止めない
（`Job#exec` は `@sandbox.error` があるときだけ `reap` する）。例外と Ctrl-C は下の表で実機で確かめた。ふつうに終わったときはコードを読んだだけ。

## 実機で確かめる

[scripts/task_close_check.rb](scripts/task_close_check.rb)。基板に送って実行する。

```console
tools/r2p2dev.py push dev-docs/device-bringup/scripts/task_close_check.rb /home/task_close_check.rb
tools/r2p2dev.py run 'ruby /home/task_close_check.rb'
```

（コンソールのページなら、コードの欄に貼って［実機で実行］でもよい。）

1. 素の Task を 20 個作る → 減る。`close` する → 戻る
2. いまの `Speaker` で短い音を 20 回 → 減る（終わったまま残る `Player` の Task が 20）
3. 残った `Player` の Task を `close` する → 戻る
4. 直した形の `Speaker`（スクリプトの中でクラスを開き直す）で 20 回 → 減らない（残る Task は 1）

4 は `Speaker` を書き換えたまま終わるので、あとで基板をリセットする。

`task_close_check.rb` はまだ流していない。代わりに、`play_mml` をくり返すスクリプトと、2 本のスクリプトを続けて流す手順で
確かめた（V1、prod、2026-10-27。`Speaker` は手元で直したものをプログラムに同梱した）。

**`play_mml` を 12 周 × 3 回（36 回）。1 周ごとに `stop` と `GC.start` のあと測る**

| `Speaker` | used（1 周目 → 12 周目） | max_free | `Task.list.size` |
|---|---|---|---|
| もとの形（`Player#start`）※ | 1 周約 9KB ずつ増え、7 周目で `NoMemoryError` | 55,952 → 1,704 | — |
| 1 つを使い回す形 | 254,328 → 254,576 | 141,168 のまま | 4 のまま |
| `close` する形 | 254,904 → 255,096 | 138,872 のまま | 3 のまま |

※ もとの形だけは、Link Pong を同梱した別のプログラムで測った。used の値は比べられないが、減り方は同じ手順。

**スクリプト A で `play_mml` してから、別のスクリプト B で `play_mml` して 1 秒待つ**（B が鳴り終われば `playing?` は `false`）

| A の終わり方 | 1 つを使い回す形 | `close` する形 |
|---|---|---|
| Ctrl-C で止める | 鳴る（`false`） | 鳴る（`false`） |
| `raise` で例外のまま終わる | **鳴らない**（`true` のまま。B をもう一度流しても同じ） | 鳴る（2 回とも `false`） |

## upstream に返すなら

- `MIDIBASE::MML::Player`: `stop` で自分の Task を `close` する（または Task を 1 つ使い回す）
- `mruby-task` の README に `Task#close` を書き、「終わった Task は `close` しないと残る」と明記する
