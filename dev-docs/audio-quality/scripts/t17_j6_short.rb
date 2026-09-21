# T17 (report.md A-2): J6 を GND に短絡すると、GPIO10 の PWM で出るノイズが消えるか。
# PWM（GPIO10、50%）は流しっぱなしにして、A ボタン（GPIO22）で段階を進める。
# ジャンパは鳴っている最中に付け外ししてよい（J6 の手前に 1kΩ×2 があるので最大 1.7mA）。
#   短絡でノイズが消える → 信号線（フィルタ → J6 → C24）を通ってアンプに入っている（候補 ①/②）。次は B-1
#   短絡しても残る       → 信号線を通らずに届いている（GND / 電源の回り込み ③、または IN± の
#                          高インピーダンス節への空間的な結合）。次は A-3（GPIO11 に負荷）
# 150kHz のあと、フィルタを最も抜けやすい 20kHz でも同じことをする。
#
# ⚠ 短絡するのは J6 だけ。J3 は GPIO 出力の直結になるので短絡しない。
# ⚠ PSG を使う前に流すこと。
require 'gpio'
require 'pwm'

BTN_A = 22

def wait_a(msg)
  puts msg
  a = GPIO.new(BTN_A, GPIO::IN | GPIO::PULL_UP)
  sleep_ms 300
  while a.read == 1
    sleep_ms 20
  end
  while a.read == 0
    sleep_ms 20
  end
  sleep_ms 200
end

amp = GPIO.new(23, GPIO::OUT)
pwm = PWM.new(10, frequency: 150000, duty: 0)
amp.write(1)
sleep_ms 1000

[150000, 20000].each do |hz|
  puts "== #{hz / 1000}kHz 50% を出しっぱなしにする"
  pwm.frequency(hz)
  pwm.duty(50)
  wait_a("T17-1: ジャンパなし。ノイズを覚えたら A")
  wait_a("T17-2: J6 と GND をジャンパで短絡。変わったか聴いたら A")
  wait_a("T17-3: ジャンパを外す。戻ったか聴いたら A")
  pwm.duty(0)
  sleep_ms 1000
end

pwm.frequency(0)
amp.write(0)
puts "T17: おわり"
