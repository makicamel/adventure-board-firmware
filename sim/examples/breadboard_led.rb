# ブレッドボードの赤 LED を点滅させる。下の配線のとおりに挿す（シミュレータは読み込むとこの配線になる）。
# 抵抗を 2 本つなぐと暗くなる。

# 配線:
#   wire J1-5 a3        J1 の 02（GPIO2）から a3 へジャンパ線
#   resistor b3 b7      抵抗 1kΩ
#   led c7 c9           赤 LED。長い足（＋）を c7、短い足（−）を c9
#   wire J1-3 d9        d9 から J1 の G（GND）へジャンパ線

led = GPIO.new(2, GPIO::OUT)   # GPIO2 を出力にする。1 を書くと 3.3V、0 で 0V

while true
  led.write(1)
  sleep_ms 500
  led.write(0)
  sleep_ms 500
end
