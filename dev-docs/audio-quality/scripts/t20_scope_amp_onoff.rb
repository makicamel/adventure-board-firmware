# T20 (report.md A-4b): J6 の波形が「アンプがあるから」か「フィルタ側の問題」かを分ける。
# 同じ PWM をアンプ OFF（SD Low）と ON で出し、J6 をオシロで比べる。A ボタン（GPIO22）で進める。
#   アンプ OFF で J6 がきれいな 150kHz の三角波（約 0.15Vpp）、ON で大きく崩れる
#     → アンプが J6 に何かを戻している（出力の回り込み、または入力段の非線形）。候補 ②
#   アンプ OFF でも同じ大きさ・同じ崩れ
#     → フィルタ／配線側の問題。GPIO10 か生の配線から J6 の節に直接乗っている
# 0V の状態も OFF / ON で比べる（T19-1 で見えた 75mVpp のハッシュがアンプ由来か）。
#
# オシロ: J6、X1、AC、200mV/div（PWM 中）/ 10mV/div（0V 中）、2µs/div と 10µs/div。残光は Min。
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
audio = GPIO.new(10, GPIO::OUT)
audio.write(0)

amp.write(0)
wait_a("T20-1: アンプ OFF、GPIO10=0V（J6 の床。測ったら A）")
amp.write(1)
wait_a("T20-2: アンプ ON、GPIO10=0V（T19-1 と同じ。測ったら A）")
amp.write(0)
sleep_ms 500

pwm = PWM.new(10, frequency: 150000, duty: 50)
wait_a("T20-3: アンプ OFF、150kHz 50%（J6 は純粋にフィルタの出力。測ったら A）")
amp.write(1)
wait_a("T20-4: アンプ ON、150kHz 50%（T19-3 と同じ。測ったら A）")
amp.write(0)
sleep_ms 500

pwm.frequency(20000)
wait_a("T20-5: アンプ OFF、20kHz 50%（測ったら A）")
amp.write(1)
wait_a("T20-6: アンプ ON、20kHz 50%（測ったら A）")

pwm.duty(0)
pwm.frequency(0)
amp.write(0)
puts "T20: おわり"
