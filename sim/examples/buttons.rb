# ボタンでドットを動かす。
# 画面のボタンでも、キーボード（矢印キー / Z / X）でも動く。
#
# ボタンはエッジ割り込みで拾っている（実機は picoruby-irq、ここはその代替）。
# 押下はキューに積まれるので、どんなに短いクリックでも、
# ループがどんなに遅くても、1 回の押しは必ず 1 回として取り出せる。
#
#   buttons.take_press   溜まった押下を 1 つ取り出す（無ければ nil）
#   buttons.pressed?(:a) いま押されているか
#
# オートリピート（押しっぱなしで連続）はここで作る。
# 押した瞬間の 1 歩はキューから、その後の連続は pressed? を数えて。

DELAY = 6      # 最初の 1 歩のあと、これだけ待ってから
INTERVAL = 2   # この間隔で繰り返す（every の tick 数）

$x = 8
$y = 8
$held = { up: 0, down: 0, left: 0, right: 0 }

def move(name)
  $x -= 1 if name == :left
  $x += 1 if name == :right
  $y -= 1 if name == :up
  $y += 1 if name == :down
  $x = 1 if $x < 1
  $x = 16 if 16 < $x
  $y = 1 if $y < 1
  $y = 16 if 16 < $y
end

every(60) do
  # 押した瞬間の 1 歩。取りこぼさない。
  buttons.each_press do |name|
    move(name)
    $held[name] = 0 if $held.key?(name)
  end

  # 押しっぱなしのリピート。
  $held.each_key do |name|
    if buttons.pressed?(name)
      n = $held[name] + 1
      $held[name] = n
      move(name) if DELAY < n && (n - DELAY - 1) % INTERVAL == 0
    else
      $held[name] = 0
    end
  end

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
