# T18 (report.md A-3): 音声に繋がっていない GPIO11 に、基板のフィルタ 1 段目と同じ負荷
# （1kΩ → 3.3nF → GND）を外付けして 150kHz 50% の PWM を出す。
# GPIO10（音声）は 0V 固定。負荷の充放電電流だけが GPIO10 と同じ大きさで流れる。
#   負荷を付けるとノイズ → 充放電電流が GND / 電源を回り込んでアンプに届いている（候補 ③ = H が復活）
#   負荷を付けても無音   → ③ は否定。ノイズは GPIO10 の信号線か、その配線固有の結合
# 負荷の付け方: J1 の 9 番（GPIO11）→ 1kΩ → 3.3nF → J1 の 2 番か 3 番（GND）。ブレッドボードで可。
# 電流を増やして感度を上げるなら 3.3nF を 10nF にする。
# PWM は流しっぱなしにして、A ボタン（GPIO22）で段階を進める。負荷は鳴っている最中に付け外ししてよい。
#
# ⚠ GPIO11 は GPIO10 と同じ PWM スライスなので、PSG を使う前に流すこと。
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
amp.write(1)
sleep_ms 1000

puts "== GPIO11（J1 の 9 番）に 150kHz 50% を出しっぱなしにする。GPIO10 は 0V"
other = PWM.new(11, frequency: 150000, duty: 50)
wait_a("T18-1: 負荷なし。無音のはず。確かめたら A")
wait_a("T18-2: GPIO11 → 1kΩ → 3.3nF → GND を付ける。聴いたら A")
wait_a("T18-3: 負荷を外す。聴いたら A")
other.duty(0)
other.frequency(0)
sleep_ms 1000

puts "T18-4: 比較: GPIO10（音声）に 150kHz 50% 5 秒"
pwm = PWM.new(10, frequency: 150000, duty: 50)
sleep_ms 5000
pwm.duty(0)
pwm.frequency(0)

amp.write(0)
puts "T18: おわり"
