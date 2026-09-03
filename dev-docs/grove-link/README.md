# GROVE リンク — 基板 2 枚を繋ぐ

同じ基板 2 枚を GROVE-B で双方向に通信させる。**箱に入っているストレートケーブル
のまま**、2 枚とも同じコードで動かすのが目標。

| 文書 | 内容 |
|---|---|
| [plan.md](plan.md) | なぜ PIO なのか、PIO で作る UART の設計 |
| [report.md](report.md) | 実機（ループバック）での検証結果。**なぜ Ruby のポーリングを捨てて DMA にしたか**、RP2350 で踏んだ罠 |

実装: `lib/picorubykaigi01/grove_link.rb`、
[`examples/grove_link_chat.rb`](../../examples/grove_link_chat.rb)。

受信は [`mrbgems/picoruby-pio-uart`](../../mrbgems/picoruby-pio-uart/) が
**DMA のリングバッファ**で受ける。プロセッサを通らないので、ループが遅れても
データは失われない。

**実機ループバックで検証済み**（500ms 放置しても 200 バイト無傷、
全バイト値が誤り 0 で往復、送信は 11,712 バイト/秒）。
**基板 2 枚での確認は未了**（試作基板待ち）。
