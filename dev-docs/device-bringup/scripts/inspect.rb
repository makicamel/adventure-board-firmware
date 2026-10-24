# 検品: LED 全点灯 → 音 → ボタン 6 個 を順に確かめる。コンソールの「実機で実行」で送る（基板には入れない）。
#   1. 全部の LED が 3 秒光る（消えている点が無いか見る）。緑のステータス LED も点く
#   2. ドレミファソラシドが鳴る
#   3. ボタンの位置に暗い四角が 6 つ出る。押したボタンの四角が明るくなり、短い音が鳴る。6 個とも押すと "OK" と和音
# 全点灯と音は同時に出さない（USB の 500mA を超えることがあるため）。
require 'adventure_board'
GC.start

matrix = AdventureBoard.matrix
buttons = AdventureBoard.buttons
speaker = AdventureBoard.speaker
led = AdventureBoard.status_led

# 1. LED 全点灯
led.on
matrix.fill(0xFF)
matrix.show
sleep_ms 3000
matrix.clear
matrix.show
led.off

# 2. 音
speaker.reset
speaker.play_mml("t120 o4 l8 c d e f g a b > c4")
sleep_ms 100
while speaker.playing?
  sleep_ms 50
end

# 3. ボタン。基板の上の並びに合わせた 2×2 の四角（左上の x, y）
BOXES = {
  up: [4, 3], left: [1, 7], right: [7, 7], down: [4, 11],
  b: [11, 9], a: [14, 6]
}

def draw_box(matrix, pos, pwm)
  x = pos[0]
  y = pos[1]
  matrix.set(x, y, pwm)
  matrix.set(x + 1, y, pwm)
  matrix.set(x, y + 1, pwm)
  matrix.set(x + 1, y + 1, pwm)
end

seen = {}
BOXES.each { |name, pos| draw_box(matrix, pos, 0x10) }
matrix.show
puts "ボタンを 6 個とも押してください"

while seen.size < BOXES.size
  buttons.each_press do |name|
    next unless BOXES[name]
    puts "#{name} OK" unless seen[name]
    seen[name] = true
    draw_box(matrix, BOXES[name], 0xFF)
    matrix.show
    led.toggle
    speaker.play_mml("o5 l32 c")
  end
  sleep_ms 20
end

sleep_ms 300
matrix.clear_drawing
matrix.pen = 0xFF
matrix.draw_text("OK", 0, 0)
matrix.blit
matrix.show
led.on
speaker.play_mml(["t150 o4 l4 c", "t150 o4 l4 e", "t150 o4 l4 g"])
puts "検品 OK"
