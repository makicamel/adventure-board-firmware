# T21 (report.md A-8): CPU が眠ると PWM が止まる、を耳で確かめる。
# R2P2 は暇なとき __wfi で眠り、そのあいだ PWM のクロックは止まる設定になっている
# （picoruby-machine の picorb_hal_init が sleep_en0 = 0 にしている）。
# 同じ 150kHz 50%（無音のはず）を出したまま、待ち方だけを変える。
#   ① sleep_ms で待つ（CPU が眠る）      → これまでどおりノイズが出るはず
#   ② 空ループで待つ（CPU が眠らない）   → PWM が連続して出て、無音になるはず
# これを 3 回繰り返す。②だけ静かなら原因は確定。
# オシロがあれば J3（X1、DC、1V/div、2µs/div）: ②のあいだは切れ目のない矩形波になる。
# ⚠ PSG を使う前に流すこと。
require 'gpio'
require 'pwm'

def busy_wait_ms(ms)
  limit = Machine.uptime_us + ms * 1000
  while Machine.uptime_us < limit
  end
end

amp = GPIO.new(23, GPIO::OUT)
amp.write(0)
pwm = PWM.new(10, frequency: 150000, duty: 50)
sleep_ms 500
amp.write(1)

3.times do |i|
  puts "T21-#{i + 1}a: sleep_ms で待つ（CPU が眠る）5 秒"
  sleep_ms 5000
  puts "T21-#{i + 1}b: 空ループで待つ（CPU が眠らない）5 秒"
  busy_wait_ms 5000
end

amp.write(0)
pwm.duty(0)
pwm.frequency(0)
puts "T21: おわり"
