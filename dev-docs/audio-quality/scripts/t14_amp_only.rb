# T14: R45 を外した状態で、J6 に外部の音（スマホのイヤホン出力など）を流し込んで聴く。
# このスクリプトはアンプを有効にして待つだけ。GPIO10 は 0V に固定する。
#   きれいに鳴る → アンプ・スピーカー・周辺は健全。原因は前段（PWM とフィルタ）
#   ざらざら     → アンプ以降の問題
require 'gpio'

amp = GPIO.new(23, GPIO::OUT)
pin = GPIO.new(10, GPIO::OUT)
pin.write(0)
amp.write(1)
puts "T14: アンプ有効。J6 に音を入れて 60 秒聴く"
sleep_ms 60000
amp.write(0)
puts "T14: おわり"
