# 緑のステータス LED を点滅させる。A を押しているあいだは点きっぱなし、B でドットが増える。
# （隣の赤い LED は電源の表示で、プログラムからは操作できない）

require 'adventure_board/led_matrix'   # LED マトリクス
GC.start                               # 読み込みで使ったメモリを片付ける
require 'adventure_board/buttons'      # ボタン
GC.start
require 'adventure_board/status_led'   # ステータス LED
GC.start

matrix = AdventureBoard.matrix         # ライブラリから使う部品を取り出す
buttons = AdventureBoard.buttons
led = AdventureBoard.status_led

t = 0
while true
  t += 1

  if buttons.pressed?(:a)
    led.on                 # A を押しているあいだは点灯
  elsif (t % 10) == 0
    led.toggle             # 10 周（1 秒）ごとに点滅を切り替える
  end

  buttons.each_press do |name|                                      # 押されたボタンを順に取り出す
    matrix.set(rand(16) + 1, rand(16) + 1, 0x80) if name == :b      # B ならでたらめな位置に 1 点
    matrix.show
  end

  sleep_ms 100
end
