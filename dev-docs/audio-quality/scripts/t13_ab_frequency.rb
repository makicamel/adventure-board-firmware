# T13: 「キャリアの周波数によらない」を確かめ直す聴き比べ。50% の PWM を、無音を挟んで
# 20kHz と 2MHz を交互に 3 回。そのあと可聴の 5kHz / 10kHz（「ピー」が聞こえる）で、
# 音程の上にノイズが乗るか。
#   2MHz のほうがはっきり小さい → フィルタを抜けたキャリアが原因（report.md 候補 1）
#   同じ大きさ                   → 信号線以外の経路（候補 2 か 3）
# J6 を GND に短絡した状態でも流せる（ノイズが消えるかを見る）。
#
# ⚠ PSG を使う前に流すこと。
require 'gpio'
require 'pwm'

amp = GPIO.new(23, GPIO::OUT)
pwm = PWM.new(10, frequency: 20000, duty: 0)
amp.write(1)
sleep_ms 1000

3.times do |i|
  puts "T13-#{i + 1}a: 20kHz 50%"
  pwm.frequency(20000)
  pwm.duty(50)
  sleep_ms 3000
  pwm.duty(0)
  puts "T13-#{i + 1}: 無音"
  sleep_ms 1500
  puts "T13-#{i + 1}b: 2MHz 50%"
  pwm.frequency(2000000)
  pwm.duty(50)
  sleep_ms 3000
  pwm.duty(0)
  puts "T13-#{i + 1}: 無音"
  sleep_ms 1500
end

[5000, 10000].each do |hz|
  puts "T13-c: #{hz / 1000}kHz 50%（音程が聞こえる）"
  pwm.frequency(hz)
  pwm.duty(50)
  sleep_ms 3000
  pwm.duty(0)
  sleep_ms 1000
end

pwm.frequency(0)
amp.write(0)
puts "T13: おわり"
