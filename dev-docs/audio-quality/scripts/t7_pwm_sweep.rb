# T7: 素の矩形波の高さを 100Hz から 2kHz まで半音ずつ上げる（1 音 250ms）。
# 特定の高さでだけビビる・歪むなら、スピーカーや基板の共振（H4）。
# 出力に周波数を出すので、気になった高さを覚えておく。
#
# ⚠ T1 と同じく、PSG を使っていない起動直後に流すこと。
require 'gpio'
require 'pwm'

amp = GPIO.new(23, GPIO::OUT)
pwm = PWM.new(10, frequency: 100, duty: 0)
amp.write(1)
sleep_ms 300

f = 100.0
while f <= 2000.0
  hz = f.to_i
  puts "T7: #{hz}Hz"
  pwm.frequency(hz)
  pwm.duty(50)
  sleep_ms 250
  f = f * 1.0595
end

pwm.duty(0)
pwm.frequency(0)
amp.write(0)
puts "T7: おわり"
