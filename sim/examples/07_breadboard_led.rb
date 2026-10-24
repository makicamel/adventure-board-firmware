# チュートリアル 7: ブレッドボードの LED を点滅させる。下の配線のとおりに挿す（シミュレータは読み込むとこの配線になる）。

# 配線:
#   wire J1-5 a13       J1 の 02（GPIO2）から a13 へジャンパ線
#   resistor b13 b9     抵抗 1kΩ
#   led c9 g10          青 LED。長い足（＋）を c9、短い足（−）を溝の向こうの g10
#   wire h10 J1-3       h10 から J1 の G（GND）へジャンパ線

led = GPIO.new(2, GPIO::OUT)   # GPIO2 を出力にする

while true
  led.write(1)    # 3.3V を出す → 光る
  sleep_ms 500
  led.write(0)    # 0V にする → 消える
  sleep_ms 500
end
