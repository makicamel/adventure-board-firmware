# ボタンでドットを動かす。
# 画面のボタンでも、キーボード（矢印キー / Z / X）でも動く。
#
# repeat? は「押した瞬間に 1 回」、そのあと少し間を置いてから
# 連続で反応する（キーボードのオートリピートと同じ）。
# 押しっぱなしで一気に進んでほしくないので、pressed? ではなくこちらを使う。
#
# every は次に Run するまで繰り返し呼ばれる。呼ばれる直前に
# buttons.update が走るので、自分で呼ぶ必要はない。
$x = 8
$y = 8

every(60) do
  $x -= 1 if buttons.repeat?(:left)
  $x += 1 if buttons.repeat?(:right)
  $y -= 1 if buttons.repeat?(:up)
  $y += 1 if buttons.repeat?(:down)
  $x = 1 if $x < 1
  $x = 16 if 16 < $x
  $y = 1 if $y < 1
  $y = 16 if 16 < $y

  matrix.clear
  # A は押している間ずっと効かせたいので pressed? を使う。
  matrix.set($x, $y, buttons.pressed?(:a) ? 0xFF : 0x50)
  if buttons.pressed?(:b)
    i = 1
    while i <= 16
      matrix.set(i, $y, 0x18)
      matrix.set($x, i, 0x18)
      i += 1
    end
  end
  matrix.show
end
