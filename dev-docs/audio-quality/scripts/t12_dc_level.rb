# T12: GPIO10 が 3.3V につながっている時間の割合で、ノイズの大きさが変わるか。
# 仮説: High のときピンは 3.3V 電源に直結なので、電源の可聴域のノイズが
# RC フィルタ（18kHz より上しか落とさない）を素通りしてアンプに入る。
#   3.3V 固定でもノイズ、かつデューティに比例して大きくなる → 3.3V 電源のノイズ
#   3.3V 固定では静か                                    → 切り替わること自体が原因（別の説明が要る）
# 各 4 秒。
#
# ⚠ PSG を使う前に流すこと。
require 'gpio'
require 'pwm'

amp = GPIO.new(23, GPIO::OUT)
pin = GPIO.new(10, GPIO::OUT)
pin.write(0)
amp.write(1)
sleep_ms 1000

puts "T12-1: GPIO10 を 0V に固定"
sleep_ms 4000

puts "T12-2: GPIO10 を 3.3V に固定（PWM なし）"
pin.write(1)
sleep_ms 4000
pin.write(0)
sleep_ms 1000

pwm = PWM.new(10, frequency: 150000, duty: 0)
[10, 25, 50, 75, 90].each do |duty|
  puts "T12-3: 150kHz デューティ #{duty}%"
  pwm.duty(duty)
  sleep_ms 4000
end

pwm.duty(0)
pwm.frequency(0)
amp.write(0)
puts "T12: おわり"
