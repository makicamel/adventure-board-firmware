# I2C の OLED（SSD1306 / SSD1315、128×64）に文字を出し、枠の中でボールを跳ねさせる。
# つなぎ方: OLED の SDA → J1 の 02（GPIO2）、SCL → 03（GPIO3）、VCC → 3V3、GND → G。
# 実機専用（シミュレータには OLED が無い）。

require 'i2c'
require 'ssd1306'   # OLED を描く gem（ファームに入っている）

STEP_MS = 30        # 1 コマの長さ
BALL = 4            # ボールの大きさ（ドット）

i2c = I2C.new(unit: :RP2040_I2C1, sda_pin: 2, scl_pin: 3, frequency: 400_000)   # J1 の 02 / 03 は I2C1
oled = SSD1306.new(i2c: i2c)          # アドレスは 0x3C（多くのモジュールの既定）。作ると画面が消える

oled.draw_text(:shinonome_min12, 0, 0, "Adventure Board")   # フォントと位置と文字。描くのは画面のメモリで、まだ映らない
oled.draw_text(:shinonome_min16, 0, 18, "こんにちは")
oled.draw_rect(0, 40, 128, 24, 1, false)                   # x, y, 幅, 高さ, 色（1 が点灯）, 塗りつぶすか
oled.update_display                                        # ここで OLED に送る

x = 10
y = 44
dx = 3
dy = 1

while true
  started = Machine.uptime_us / 1000   # 時計で測るので、描く時間が変わっても速さは同じ

  oled.erase(1, 41, 126, 22)                  # 枠の内側だけ消す
  oled.draw_rect(x, y, BALL, BALL, 1, true)   # ボール
  oled.update_display_optimized               # 変わったところだけ送る（全部送るより速い）

  x += dx
  y += dy
  dx = -dx if x <= 1 || 127 - BALL <= x       # 枠に当たったら向きを変える
  dy = -dy if y <= 41 || 63 - BALL <= y

  wait = STEP_MS - (Machine.uptime_us / 1000 - started)
  sleep_ms wait if 0 < wait
end
