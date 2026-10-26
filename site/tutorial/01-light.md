# 1. 1 ドット光らせる

LED マトリクスの左上の 1 つだけを光らせます。

<<< @/../sim/examples/01_light.rb

<ConsoleLink example="01_light.rb" />

コンソールで Run を押すと、左上が 1 つ光ります。

## 1 行ずつ見る

```ruby
require 'adventure_board'
GC.start
```

1 行目で基板のライブラリ `AdventureBoard` を読み込み、
2 行目で `require` の読み込みに使ったメモリを回収します。マイコンのメモリはとても小さいので、場合によっては手動でGCを動かす必要があります。

```ruby
matrix = AdventureBoard.matrix
```

LED マトリクスを取り出します。

```ruby
matrix.clear
matrix.set(1, 1)
matrix.show
```

- `clear` で全部消し
- `set(x, y)` で 1 つ点け
- `show` で **LED ドライバに送ります**

`set` しただけでは、まだ光りません。`show` を呼んだときに、それまでの変更がまとめて LED ドライバに届きます。

## 場所と明るさを変える

座標は、左上が `(1, 1)`、右下が `(16, 16)` です。
`set` の 3 つ目に数を渡すと、明るさを変えられます。0 が消灯、255 がいちばん明るい。省くと 255 です。

<<< @/../sim/examples/01_light_more.rb

<ConsoleLink example="01_light_more.rb" />

::: tip やってみよう
- 4 すみを全部光らせてみましょう
- 明るさを 0x10、0x40、0x80 と変えて、違いを見てみましょう
:::

## 明るさの数字について

LED は、数字が 2 倍になっても 2 倍明るく見えるわけではありません。実際に光らせてみて調整しましょう。
