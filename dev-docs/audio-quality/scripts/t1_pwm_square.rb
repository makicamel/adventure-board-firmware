# T1: 基準の音。PSG を通さず、picoruby-pwm で素の矩形波を GPIO10 に出す。
# PWM のキャリアも折り返しも無い、ハードだけの音。
#
# ⚠ 起動してから PSG（speaker）を一度も使っていない状態で流すこと。
#    PSG が PWM を掴んでいると取り合いになる。前に PSG を鳴らしたならリセットしてから。
# ⚠ 0〜3.3V いっぱいに振るので、PSG の 1 声より大きな音になる。
require 'gpio'
require 'pwm'

amp = GPIO.new(23, GPIO::OUT)   # PAM8302A の SD。High で鳴る
pwm = PWM.new(10, frequency: 262, duty: 0)
amp.write(1)
sleep_ms 300

[262, 440, 880].each do |f|
  puts "T1: #{f}Hz 矩形波 (duty 50%) 3 秒"
  pwm.frequency(f)
  pwm.duty(50)
  sleep_ms 3000
  pwm.duty(0)
  sleep_ms 1000
end

pwm.frequency(0)
amp.write(0)
puts "T1: おわり"
