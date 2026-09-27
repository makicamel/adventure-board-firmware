# T23: 基板自身の ADC で J6 を録り続け、ブチッが聞こえたら A ボタンで止める。
# 配線: J6 → J1 ヘッダの GPIO26（ADC0）をジャンパ線 1 本。
# 12.5kS/s・8bit で 32768 点 = 直近の 2.6 秒が RAM のリングに残る。中身は SWD で吸い出す
# （addr と oldest を控える。tools 側の手順は report.md）。
# ブチッが聞こえたら 2 秒以内に A ボタン（SW6）。押さなければ曲を繰り返し続ける。
require 'adventure_board'
GC.start

speaker = AdventureBoard.speaker
require 'gpio'

RATE = 12500
a = GPIO.new(22, GPIO::IN | GPIO::PULL_UP)

speaker.reset
puts "T23: addr=#{ADCCapture.addr} size=#{ADCCapture.size} rate=#{RATE}"
ADCCapture.start(26, RATE)
speaker.play_mml("t140 o4 l8 $ ccggaag4 ffeeddc4 r2", loop: true)

while a.read == 1
  sleep_ms 10
end
oldest = ADCCapture.stop
speaker.stop
puts "T23: stopped oldest=#{oldest}"
