# ボタンでドットを動かす。
# 画面のボタンでも、キーボード（矢印キー / Z / X）でも動く。
#
# every は次に Run するまで繰り返し呼ばれる。呼ばれる直前に
# buttons.update が走るので、自分で呼ぶ必要はない。
$x = 8
$y = 8

every(60) do
  $x -= 1 if buttons.pressed?(:left)
  $x += 1 if buttons.pressed?(:right)
  $y -= 1 if buttons.pressed?(:up)
  $y += 1 if buttons.pressed?(:down)
  $x = 1 if $x < 1
  $x = 16 if 16 < $x
  $y = 1 if $y < 1
  $y = 16 if 16 < $y

  matrix.clear
  # A を押している間は明るく、B で十字を出す。
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
