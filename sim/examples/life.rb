# ライフゲーム。でたらめな配置から始めて、止まったり全滅したりしたら配り直す。
# 明るいのは生まれたばかりのセル、少し暗いのは生き残っているセル。

require 'adventure_board'
GC.start                               # 読み込みで使ったメモリを片付ける
require 'adventure_board/led_matrix'   # LED マトリクス
GC.start

N = 16
STEP_MS = 150      # 1 世代の長さ
DENSITY = 30       # 最初に生きているセルの割合（%）

# 盤面は 16×16 の配列。1 が生きている、0 が死んでいる。端は反対側とつながっている
seed = lambda do
  board = []
  y = 0
  while y < N
    row = []
    x = 0
    while x < N
      row << (rand(100) < DENSITY ? 1 : 0)   # rand(100) は 0〜99 のでたらめな数
      x += 1
    end
    board << row
    y += 1
  end
  board
end

# 次の世代。周りの 8 セルのうち、生きているのが 3 つなら生まれ、2 つか 3 つなら生き残る
step = lambda do |board|
  nxt = []
  y = 0
  while y < N
    up = board[(y + N - 1) % N]
    cur = board[y]
    down = board[(y + 1) % N]
    sums = []                          # 縦 3 セルの和を先に作っておくと、横に 3 つ足すだけで済む
    x = 0
    while x < N
      sums << up[x] + cur[x] + down[x]
      x += 1
    end
    row = []
    x = 0
    while x < N
      n = sums[(x + N - 1) % N] + sums[x] + sums[(x + 1) % N] - cur[x]   # 自分を引く
      row << ((n == 3 || (n == 2 && cur[x] == 1)) ? 1 : 0)
      x += 1
    end
    nxt << row
    y += 1
  end
  nxt
end

board = seed.call
before = nil       # 1 つ前の世代
before2 = nil      # 2 つ前の世代

while true
  started = Machine.uptime_us / 1000   # 時計で測るので、基板でもシミュレータでも同じ速さ

  matrix.clear
  alive = 0
  y = 0
  while y < N
    x = 0
    while x < N
      if board[y][x] == 1
        alive += 1
        born = before.nil? || before[y][x] == 0
        matrix.set(x + 1, y + 1, born ? 0xFF : 0x70)
      end
      x += 1
    end
    y += 1
  end
  matrix.show

  # 全滅した、変わらなくなった、2 つの形を行き来するだけになった → 配り直す
  if alive == 0 || board == before || board == before2
    sleep_ms 800
    board = seed.call
    before = nil
    before2 = nil
  else
    before2 = before
    before = board
    board = step.call(board)
  end

  wait = STEP_MS - (Machine.uptime_us / 1000 - started)
  sleep_ms wait if 0 < wait
end
