# GROVE リンク — 基板 2 枚を繋ぐ

同じ基板 2 枚を GROVE-B で双方向に通信させる。**箱に入っているストレートケーブル
のまま**、2 枚とも同じコードで動かすのが目標。

| 文書 | 内容 |
|---|---|
| [plan.md](plan.md) | なぜ PIO なのか、PIO で作る UART の設計、実装手順 |

現状: `lib/picorubykaigi01/grove_link.rb` と
[`examples/grove_link_chat.rb`](../../examples/grove_link_chat.rb) を実装済み。
**PIO UART は Pico 2 W のループバックで検証済み**（1〜127 の全バイトが誤り 0 で
往復、行の送受信も可）。**基板 2 枚での確認は未了**（試作基板待ち）。
