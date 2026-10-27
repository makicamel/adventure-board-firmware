# コンソールから基板へファイルを送る — 計画（未実装）

2026-10-27 に方針を決めた。**実装はまだ。** 作り始める前にこの文書を読み直す。

きっかけは、終わった Task がメモリに残る件（[../device-bringup/task-memory.md](../device-bringup/task-memory.md)）。
量産基板にはもうファームを書いたので、直すのは `/lib/adventure_board/speaker.rb` の差し替えになる。
それを参加者の基板に届ける手段が要る。

## 決めたこと: 2 つとも置く

| 機能 | 誰向け | すること |
|---|---|---|
| ［ライブラリを最新にする］ | 参加者 | ページが持っている `lib/`（「ライブラリのコードを見る」で読み込み済みのもの）を、基板の `/lib` にまとめて書く |
| 「▸ 基板にファイルを送る（上級者向け）」 | 開発者・上級者 | ページのいちばん下に、ふだんは閉じて置く。ファイルを選ぶ欄、書き込み先のパスの欄（初期値は `/home/<ファイル名>`）、［転送］。同じパスのファイルは上書きする。`/lib` に書くときだけ確認を出す |
| ［ライブラリを工場出荷の状態に戻す］ | 両方 | 上の欄に一緒に置く。`/etc/adventure-board-files` を消して再起動する（下の「`/lib` を戻す仕組み」） |

どれもファームは変えずにページだけで作れる。量産基板にそのまま使える。

## すでにあるもの

- **基板側**: PicoModem（ファームに入っている）の `FILE_WRITE` は、任意のパスに書ける
  （`mrbgems/picoruby-picomodem/mrblib/picomodem.rb` の `handle_file_write`）。同じパスのファイルは消してから書き、CRC32 を返す。
  `FILE_READ`（読み出し）もある
- **ページ側**: `SimDevice#upload(source, path)`（`sim/sim_device.rb`）。「実機で実行」が `/home/run.rb` に書くのに使っている

## 作るときに気をつけること

- **書き込み先のフォルダが無いと失敗する。** PicoModem はフォルダを作らない（`File.open(path, "w")` がエラーになる）。
  転送の前にシェルで `mkdir` を送るか、エラーをわかりやすく出す
- **ファイルを選ぶ欄から Ruby に中身を渡すところで、0 のバイトが切れないか確かめる。** JS と Ruby の受け渡しは文字列を
  C の文字列として扱うことがある（CLAUDE.md の「ブリッジは文字列を C 文字列として扱う」）。基板へ送る経路（`serial_write`）は
  長さ付きのバイト列なので問題ない
- **`/lib` を戻す仕組み。** ファームは起動のたびに、自分が持っているファイル一式のハッシュと `/etc/adventure-board-files` を比べ、
  同じなら何も書かない（`mrbgems/picoruby-r2p2/ports/rp2040/system_files.c`）。なので、`/lib` を壊すと**同じファームを焼き直しても
  戻らない**。`/etc/adventure-board-files` を消して再起動すれば、`/lib` を書き直す（`/home/examples` は、あるファイルには触らない）
- 公開中のコンソールに出すには、作ったあとで `gh workflow run deploy.yml -R picorubykaigi/adventure-board-console` を手で起動する

## `.mrb`（バイトコード）を送る

Ruby のソースをページで前もってバイトコードにして送れば、基板の上でコンパイルしなくて済む。
`require` で要る大きな連続領域（ソースの約 6 倍。[../device-bringup/require-memory.md](../device-bringup/require-memory.md)）が要らなくなり、
大きいプログラムが `NoMemoryError` になりにくい。

**ファームを変えずにページだけで作れそう。** 以下はコードを読んで確かめたことで、実際に `.mrb` を作って基板で動かしてはいない。
作り始めるときは、まず 1 本送って動くかを確かめる。

| 必要なこと | 状況 |
|---|---|
| ページで `.mrb` を作る | wasm に `PicoRubyVM::InstructionSequence.compile(src).to_binary` がある（`picoruby-wasm` が `picoruby-picorubyvm` に依存している）。中身は `mrc_dump_irep` で、ファームと同じコンパイラ |
| 中身の形式が基板と合う | 形式に効く設定は wasm（`build_config/picoruby-wasm.rb`）と基板（`build_config/r2p2-picoruby-pico2.rb`）で同じ: `MRB_INT64` / `MRB_NO_BOXING` / `MRB_32BIT`。バイトコードの版（RITE）も同じソースから作っている |
| 0 のバイトを含むデータを送る | 送る経路は長さ付きのバイト列。いまの転送でも 0 のバイトを含むフレームを送っている |
| 基板が実行する | `Sandbox#load_file`（`mrbgems/picoruby-sandbox/mrblib/sandbox.rb`）は、先頭が `RITE_VERSION` ならコンパイルせずに実行する。`RITE` で始まって版が違えば `invalid RITE version` とはっきりエラーになる |

### `.mrb` は `.rb` より優先される

- **`require` は同じフォルダの `.mrb` を `.rb` より先に読む**（`mrbgems/picoruby-require/mrblib/require.rb` の `require_file`。
  `exts = ["mrb", "rb"]`）。`/lib/adventure_board/speaker.mrb` を置くと、そのあとでファームが `.rb` を新しくしても
  古い `.mrb` が使われ続ける。**［工場出荷の状態に戻す］は `/lib` の `.mrb` も消す**
- **起動時は `/home/app.mrb` が `/home/app.rb` より優先される**（`mrbgems/picoruby-shell/shell_executables/r2p2.rb`）。
  いまの［実機の app.rb を空にする］は `app.mrb` を止められない。`.mrb` を送れるようにするなら、このボタンで `app.mrb` も消す
- バイトコードの版は、**ページの wasm を作ったときのもの**になる。あとで upstream を取り込んで版が上がると、
  量産基板のファーム（`v2026.10.25` で固定）と合わなくなる。送る前に基板の版と比べて、合わなければ送らずに知らせる

### 使い始める範囲

- ユーザが自分のプログラムを送るとき（`/home/…`、`app.mrb`）から使い始める
- ［ライブラリを最新にする］は、最初は `.rb` のまま配る（上の「`.mrb` が優先される」問題があるため）
