# T15: 「PWM の負荷電流が 3.3V を揺らし、その揺れが GPIO10 の High に乗ってアンプに入る」説の確認。
# GPIO10 は PWM せず固定し、別の負荷（ステータス LED = GPIO16 → R31 2kΩ → D3、約 0.65mA）を PWM で揺らす。
#   T15-2（GPIO10=3.3V 固定 + LED を PWM）でノイズ、T15-1（GPIO10=0V + LED を PWM）で無音
#     → 電源の揺れが GPIO10 の High レベル経由で入っている（新しい説）
#   T15-1 でもノイズ → GPIO10 を通らずに届いている（GND / 空間の結合）
#   T15-2 が無音 → 電源説ではない。GPIO10 の負荷ループ固有
# 各 5 秒。LED は PWM 中に薄く点く。
#
# ⚠ PSG を使う前に流すこと（GPIO11 は音声の PWM と同じスライス）。
require 'gpio'
require 'pwm'

amp = GPIO.new(23, GPIO::OUT)
audio = GPIO.new(10, GPIO::OUT)
audio.write(0)
amp.write(1)
sleep_ms 1000

puts "T15-1: GPIO10=0V 固定、LED(GPIO16) を 150kHz 50% で PWM"
led = PWM.new(16, frequency: 150000, duty: 50)
sleep_ms 5000
led.duty(0)
sleep_ms 1000

puts "T15-2: GPIO10=3.3V 固定、LED を 150kHz 50% で PWM"
audio.write(1)
sleep_ms 500
led.duty(50)
sleep_ms 5000
led.duty(0)
sleep_ms 1000

puts "T15-3: GPIO10=3.3V 固定、LED を 20kHz 50% で PWM"
led.frequency(20000)
led.duty(50)
sleep_ms 5000
led.duty(0)
led.frequency(0)
sleep_ms 1000

puts "T15-4: GPIO10=3.3V 固定、GPIO11（ヘッダ、無負荷）を 150kHz 50% で PWM"
other = PWM.new(11, frequency: 150000, duty: 50)
sleep_ms 5000
other.duty(0)
other.frequency(0)
audio.write(0)
sleep_ms 1000

puts "T15-5: 参考: GPIO10 を 150kHz 50% で PWM"
pwm = PWM.new(10, frequency: 150000, duty: 50)
sleep_ms 5000
pwm.duty(0)
pwm.frequency(0)

amp.write(0)
puts "T15: おわり"
