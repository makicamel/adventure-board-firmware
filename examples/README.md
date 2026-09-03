# 実機専用サンプル

シミュレータが持っていないハードを使うサンプル。**実機でのみ動く。**

ブラウザで動くサンプルは [`../sim/examples/`](../sim/examples/) にあり、
シミュレータのページから選べる。こちらは picker に出さない。
出してしまうと、動かないものが並んで必ず失敗する。

| ファイル | 使うもの | 必要なもの |
|---|---|---|
| [grove_link_chat.rb](grove_link_chat.rb) | GROVE-B（PIO で作った UART） | 基板 2 枚。**ケーブルはストレートでよい** |
| [grove_uart_chat.rb](grove_uart_chat.rb) | GROVE-B（ハードウェア UART0） | **基板 2 枚 + クロスケーブル** |

2 枚を繋ぐなら `grove_link_chat.rb` の方を使う。ケーブルを選ばない。
`grove_uart_chat.rb` は**ハードウェア UART の使い方**として残してある。

## 動かし方

R2P2 のシェルから直接:

```
/home/examples/grove_link_chat.rb
```

シェルはパスで実行する。`grove_link_chat.rb` とだけ打っても、`PATH` は
`/bin` しか見ないので見つからない。

ファイルを送るには、ブラウザから WebSerial で（`dev-docs/webserial-console/`）か、
シェルの `vim` で書く。

## ⚠ GROVE-B のクロスケーブル

GPIO28 は UART0 TX、GPIO29 は UART0 RX にしかなれない
（ファンクション mux が UART の役割をピン番号の 4 の剰余で固定している。
28%4=0 が TX、29%4=1 が RX で、入れ替える選択肢が無い）。

したがって**同じ基板 2 枚をストレートケーブルで繋ぐと TX 同士がぶつかる**。

これを避けるために `grove_link_chat.rb` は PIO で UART を作り、片方の基板だけ
TX と RX を入れ替える。ピンの役割を選べるのが PIO の取り柄で、そのぶん
ケーブルを選ばない。設計は [dev-docs/grove-link/](../dev-docs/grove-link/)。
信号 2 本を入れ替えたケーブルが要る。

- Seeed **Grove - UART Crossover Cable 4Pin**（SS100052406）
- あるいは Grove-to-ジャンパ変換を 2 本使い、信号 2 本を交差させる

J5 のピン配列は **1=GPIO29(RX) / 2=GPIO28(TX) / 3=3V3 / 4=GND**。
発注前に実物のピン配列図と突き合わせること。電源と GND が入れ替わる製品を
掴むと危険。
