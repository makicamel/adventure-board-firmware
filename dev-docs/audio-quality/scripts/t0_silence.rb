# T0: 無音でアンプとスピーカーの雑音を聴く。何も鳴らしていないのに音がするなら、
# アンプか電源（USB の 5V）の問題。
#   1. アンプ停止（SD Low）            5 秒
#   2. アンプ動作・入力 0V              5 秒
#   3. アンプ動作・入力を真ん中の電圧   5 秒（150kHz 50% の PWM。フィルタで平らになり音は出ない）
# 2→3 の切り替わりで「プツッ」と 1 回鳴るのは直流が変わるためで、正常。
#
# ⚠ PSG を使う前に流すこと（T1 / T7 のあとなら続けて流してよい）。
require 'gpio'
require 'pwm'

amp = GPIO.new(23, GPIO::OUT)
pwm = PWM.new(10, frequency: 150000, duty: 0)

puts "T0-1: アンプ停止 5 秒"
amp.write(0)
sleep_ms 5000

puts "T0-2: アンプ動作・入力 0V 5 秒"
amp.write(1)
sleep_ms 5000

puts "T0-3: アンプ動作・入力を真ん中の電圧 5 秒"
pwm.duty(50)
sleep_ms 5000

pwm.duty(0)
pwm.frequency(0)
amp.write(0)
puts "T0: おわり"
