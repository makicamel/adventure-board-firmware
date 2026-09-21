# T19 (report.md A-4): オシロで見るために、各状態を A ボタン（GPIO22）を押すまで保つ。
# 測る場所（プローブは ×10、GND リードは短く。GND は C23 か C27 の GND 側パッドに取る）:
#   J6        フィルタを抜けてアンプ入口に届いているキャリア。計算値: 20kHz 約 1V、150kHz 約 0.15V、2MHz 約 1mV
#             （C24 の手前なので直流は PWM の平均値。50% なら 1.65V）
#   VO+ − VO− スピーカー端子（R46 / R47 の LS1 側）。2 本のプローブの差（A−B）。
#             正常なら 250kHz 前後・5V の同相スイッチングだけで、差はほぼ 0
#   C23 両端  IN− 側の基準。ここが揺れていれば GND の回り込み（候補 ③）
#   J3        生の PWM（3.3V の矩形波）。波形が崩れていないかの確認
#   C27 両端  アンプの 5V。切り替え中に揺れるか
# 見るもの: 状態 3〜5 で J6 の振幅が計算値より大きいか（候補 ①/②）、VO+−VO− が入力ゼロなのに暴れるか（②）。
#
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

amp.write(0)
audio.write(0)
wait_a("T19-0: アンプ停止、GPIO10=0V（オシロの床。測ったら A）")

amp.write(1)
wait_a("T19-1: アンプ動作、GPIO10=0V（無音のはず。測ったら A）")

audio.write(1)
wait_a("T19-2: アンプ動作、GPIO10=3.3V 固定（無音のはず。測ったら A）")

pwm = PWM.new(10, frequency: 150000, duty: 50)
wait_a("T19-3: 150kHz 50%（ノイズ。J6 の計算値 約 0.15V。測ったら A）")

pwm.frequency(20000)
wait_a("T19-4: 20kHz 50%（ノイズ。J6 の計算値 約 1V。測ったら A）")

pwm.frequency(2000000)
wait_a("T19-5: 2MHz 50%（ノイズ。J6 の計算値 約 1mV。測ったら A）")

pwm.frequency(22500)
wait_a("T19-6: 22.5kHz 50%（PSG のキャリアと同じ。測ったら A）")

pwm.frequency(440)
wait_a("T19-7: 440Hz 50%（T1 と同じ可聴の矩形波。スピーカー端子の波形。測ったら A）")

pwm.duty(0)
pwm.frequency(0)
amp.write(0)
puts "T19: おわり"
