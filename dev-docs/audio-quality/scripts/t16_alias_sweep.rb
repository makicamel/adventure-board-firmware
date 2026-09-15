# T16: アンプ内部の折り返し（PAM8302A の発振 200〜300kHz と、入力の成分との差が可聴域に落ちる）の確認。
# 50% の PWM を 200kHz → 300kHz まで 2kHz 刻み（各 0.7 秒）、次に 400 → 600kHz を 5kHz 刻みで動かす。
#   音の高さが刻みに合わせて滑らかに上がる／下がる（ピー ↔ 無音を通り過ぎる） → 折り返し。
#     無音に近づく点がアンプの発振周波数（とその 2 倍）
#   高さの変わらない雑音のまま → 折り返しではない
# 折り返しなら、対策は「フィルタを強くする」か「PWM のキャリアを発振周波数の整数倍から遠ざける」。
#
# ⚠ PSG を使う前に流すこと。
require 'gpio'
require 'pwm'

amp = GPIO.new(23, GPIO::OUT)
pwm = PWM.new(10, frequency: 200000, duty: 0)
amp.write(1)
sleep_ms 500

puts "T16-1: 200kHz → 300kHz を 2kHz 刻み（各 0.7 秒）"
f = 200000
while f <= 300000
  puts "  #{f / 1000}kHz" if f % 10000 == 0
  pwm.frequency(f)
  pwm.duty(50)
  sleep_ms 700
  f += 2000
end
pwm.duty(0)
sleep_ms 1000

puts "T16-2: 400kHz → 600kHz を 5kHz 刻み（各 0.5 秒）"
f = 400000
while f <= 600000
  puts "  #{f / 1000}kHz" if f % 25000 == 0
  pwm.frequency(f)
  pwm.duty(50)
  sleep_ms 500
  f += 5000
end
pwm.duty(0)
pwm.frequency(0)
amp.write(0)
puts "T16: おわり"
