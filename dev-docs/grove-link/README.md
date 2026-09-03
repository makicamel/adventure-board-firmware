# GROVE リンク — 基板 2 枚を繋ぐ

同じ基板 2 枚を GROVE-B で双方向に通信させる。**箱に入っているストレートケーブル
のまま**、2 枚とも同じコードで動かすのが目標。

| 文書 | 内容 |
|---|---|
| [plan.md](plan.md) | なぜ PIO なのか、PIO で作る UART の設計 |
| [report.md](report.md) | Pico 2 W 1 枚（ループバック）での検証結果と、測って直したこと |

実装: `lib/picorubykaigi01/grove_link.rb`、
[`examples/grove_link_chat.rb`](../../examples/grove_link_chat.rb)。

**PIO UART は検証済み**（1〜127 の全バイトが誤り 0 で往復、2,453 バイト/秒）。
**基板 2 枚での確認は未了**（試作基板待ち）。
