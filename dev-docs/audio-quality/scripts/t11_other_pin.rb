# T11: 音声とは繋がっていない GPIO15 で 150kHz の PWM を出す。音声の GPIO10 は 0V のまま。
#   これでもノイズが出る → フィルタを通らない経路（GND / 電源）で回り込んでいる
#   静か               → 音声のピンからフィルタを通ってアンプに入っている
# 比べるため、最後に GPIO10 側でも同じ 150kHz を出す。各 5 秒。
#
# ⚠ PSG を使う前に流すこと。
require 'gpio'
require 'pwm'

amp = GPIO.new(23, GPIO::OUT)
audio = GPIO.new(10, GPIO::OUT)
audio.write(0)
amp.write(1)
sleep_ms 1000

puts "T11-1: 何も出さない 5 秒"
sleep_ms 5000

puts "T11-2: GPIO15 に 150kHz 50% 5 秒（音声のピンは 0V）"
other = PWM.new(15, frequency: 150000, duty: 50)
sleep_ms 5000
other.duty(0)
other.frequency(0)
sleep_ms 1000

puts "T11-3: 比較: GPIO10（音声）に 150kHz 50% 5 秒"
pwm = PWM.new(10, frequency: 150000, duty: 50)
sleep_ms 5000
pwm.duty(0)
pwm.frequency(0)

amp.write(0)
puts "T11: おわり"
