# 配線:
#   wire J1-5 a13       J1 の 02（GPIO2）から a13 へ
#   resistor b13 b9     抵抗 1kΩ
#   led c9 g10          青 LED。長い足（＋）を c9、短い足（−）を g10
#   wire h10 J1-3       h10 から J1 の G（GND）へ
#   switch e3           タクトスイッチ。足は e3 e5 f3 f5
#   wire J1-6 a3        J1 の 03（GPIO3）から a3 へ
#   wire a5 J1-2        a5 から J1 の G（GND）へ

led = GPIO.new(2, GPIO::OUT)
switch = GPIO.new(3, GPIO::IN | GPIO::PULL_UP)   # 入力にする。何もつながないと 1 になる

while true
  if switch.read == 0   # 押すと GND とつながって 0 になる
    led.write(1)
  else
    led.write(0)
  end
  sleep_ms 10
end
