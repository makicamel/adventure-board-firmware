# GROVE リンク — 基板 2 枚を繋ぐ

同じ基板 2 枚を GROVE-B で双方向に通信させる。**箱に入っているストレートケーブル
のまま**、2 枚とも同じコードで動かすのが目標。

| 文書 | 内容 |
|---|---|
| [plan.md](plan.md) | なぜ PIO なのか、PIO で作る UART の設計 |
| [report.md](report.md) | 実機（ループバック）での検証結果。**なぜ Ruby のポーリングを捨てて DMA にしたか**、RP2350 で踏んだ罠 |

実装: `lib/picorubykaigi01/grove_link.rb`、
[`examples/grove_link_chat.rb`](../../examples/grove_link_chat.rb)。

使うのは**普通の `UART`** で、ユニットに `:PIO_UART0` を渡すだけ。

```ruby
UART.new(unit: :PIO_UART0, txd_pin: 28, rxd_pin: 29, baudrate: 115_200)
```

`gets` も `irq` も同じメソッドが動く。この基板で覚えたことが素の R2P2 でも
そのまま通じるようにするため、別クラスにはしなかった。
受信は [`mrbgems/picoruby-pio-uart`](../../mrbgems/picoruby-pio-uart/) が
**DMA のリングバッファ**で受ける。プロセッサを通らないので、ループが遅れても
データは失われない。upstream への変更は [../upstream-changes.md](../upstream-changes.md)。

**実機ループバックで検証済み**（500ms 放置しても 200 バイト無傷、
全バイト値が誤り 0 で往復、送信は 11,712 バイト/秒）。
**基板 2 枚でも確認済み**（2026-10-25、量産版 V1 の 2 枚、ふつうの Grove ケーブル。A→B・B→A とも 1 秒ごとの 1 行が欠けずに届いた。
確認スクリプトは [`dev-docs/device-bringup/scripts/grove_link_check.rb`](../device-bringup/scripts/grove_link_check.rb)）。
同じ起動のあいだに役割を変えて開き直すと、最初のピンのまま動くので、試すたびに再起動すること。
