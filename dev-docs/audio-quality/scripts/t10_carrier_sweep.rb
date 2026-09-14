# T10: 無音（50% の PWM）のまま、キャリアの周波数だけを変えていく。各 3 秒。
# PAM8302A は内部で 200〜300kHz で発振している（データシートの fOSC）。
#   周波数によってノイズが大きく変わる（特に高いほど静か） → アンプの発振と混ざっている
#   どの周波数でも同じようにうるさい                   → PWM の電流が GND / 電源を回り込んでいる
# 出力欄の周波数と、うるさかったかどうかを控えておく。
#
# ⚠ PSG を使う前に流すこと（T0 / T1 / T7 のあとなら続けてよい）。
require 'gpio'
require 'pwm'

amp = GPIO.new(23, GPIO::OUT)
pwm = PWM.new(10, frequency: 20000, duty: 0)
amp.write(1)
sleep_ms 1000

[20000, 40000, 60000, 80000, 100000, 125000, 150000, 200000,
 250000, 300000, 400000, 600000, 1000000, 2000000].each do |hz|
  puts "T10: #{hz / 1000}kHz"
  pwm.frequency(hz)
  pwm.duty(50)
  sleep_ms 3000
end

pwm.duty(0)
pwm.frequency(0)
amp.write(0)
puts "T10: おわり"
