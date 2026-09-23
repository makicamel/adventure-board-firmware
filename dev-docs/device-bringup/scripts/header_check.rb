# J1（ブレッドボード用 2x10 ソケット）の疎通確認。
#   1 段階目: ジャンパなし。GPIO を 1 本ずつ High / Low にして残りを読み、短絡を探す
#   2 段階目: ジャンパで折り返し。2 本ずつの組と、25-26-27 の数珠つなぎ（13 本を 1 周で）
#   3 段階目: 電源ピン。3V3 → GPIO26(ADC0)、5V → 10k:10k で分圧して GPIO27(ADC1)、GND → プルアップした GPIO
# 段階の切り替えは基板の A ボタン（GPIO22）。出力欄の指示どおりにジャンパを刺してから A を押す。
#
# ⚠ 5V を GPIO に直接入れない（3.3V が上限）。
# ⚠ GPIO11 は音声の PWM と同じスライスなので、PSG を使う前に流す。GPIO16 はステータス LED 兼用（読み書きは問題ない）。
require 'gpio'
require 'adc'

PINS = [2, 3, 8, 9, 11, 12, 13, 14, 15, 16, 25, 26, 27]
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

def all_inputs(flags)
  PINS.each { |p| GPIO.new(p, flags) }
end

# --- 1. ジャンパなし ------------------------------------------------------
puts "== 1. ジャンパなし。何も刺さないで A を押す"
wait_a("   （A を押すと開始）")
bad = 0
all_inputs(GPIO::IN | GPIO::PULL_DOWN)
PINS.each do |p|
  o = GPIO.new(p, GPIO::OUT)
  o.write(1)
  sleep_ms 2
  hit = PINS.reject { |q| q == p }.select { |q| GPIO.new(q, GPIO::IN | GPIO::PULL_DOWN).read == 1 }
  o.write(0)
  GPIO.new(p, GPIO::IN | GPIO::PULL_DOWN)
  unless hit.empty?
    puts "   NG: GPIO#{p} を High にすると GPIO#{hit.join(',')} も High（短絡）"
    bad += 1
  end
end
all_inputs(GPIO::IN | GPIO::PULL_UP)
sleep_ms 5
low = PINS.select { |p| GPIO.new(p, GPIO::IN | GPIO::PULL_UP).read == 0 }
puts "   NG: プルアップしても Low: GPIO#{low.join(',')}（GND 短絡?）" unless low.empty?
all_inputs(GPIO::IN | GPIO::PULL_DOWN)
sleep_ms 5
high = PINS.select { |p| GPIO.new(p, GPIO::IN | GPIO::PULL_DOWN).read == 1 }
puts "   NG: プルダウンしても High: GPIO#{high.join(',')}（電源短絡?）" unless high.empty?
bad += low.size + high.size
puts "   1. #{bad == 0 ? 'OK: 短絡なし' : "NG #{bad} 件"}"

# --- 2. 折り返し --------------------------------------------------------
def loop_pair(a, b)
  ok = true
  [[a, b], [b, a]].each do |o_pin, i_pin|
    i = GPIO.new(i_pin, GPIO::IN | GPIO::PULL_DOWN)
    o = GPIO.new(o_pin, GPIO::OUT)
    o.write(1); sleep_ms 2; r1 = i.read
    o.write(0); sleep_ms 2; r0 = i.read
    GPIO.new(o_pin, GPIO::IN | GPIO::PULL_DOWN)
    unless r1 == 1 && r0 == 0
      puts "   NG: GPIO#{o_pin} -> GPIO#{i_pin}: High->#{r1} Low->#{r0}"
      ok = false
    end
  end
  ok
end

# 13 本を一度に。GPIO27 は 25-26-27 の数珠つなぎ（26 を真ん中に 2 本）で、
# 組の中の全部の 2 本について両方向を試す。
GROUPS = [[2, 3], [8, 9], [11, 12], [13, 14], [15, 16], [25, 26, 27]]
puts "== 2. ジャンパで次の組をつなぐ: 2-3  8-9  11-12  13-14  15-16  25-26 と 26-27（26 を真ん中に 2 本）"
wait_a("   （刺したら A を押す）")
all_inputs(GPIO::IN | GPIO::PULL_DOWN)
ng = 0
GROUPS.each do |g|
  g.each_with_index do |a, i|
    g.each_with_index do |b, j|
      next unless i < j
      ng += 1 unless loop_pair(a, b)
    end
  end
end
puts "   2. #{ng == 0 ? 'OK: 13 本すべて 出せる・読める・J1 まで届いている' : "NG #{ng} 組"}"

# --- 3. 電源ピン --------------------------------------------------------
puts "== 3. 電源ピン。ジャンパを全部抜き、次を刺す:"
puts "     3V3 → GPIO26 （直結でよい）"
puts "     5V → 10kΩ → GPIO27、GPIO27 → 10kΩ → GND （必ず分圧。5V を直接入れない）"
puts "     GND（どれか 1 本）→ GPIO2、別の GND → GPIO3"
wait_a("   （刺したら A を押す）")
v26 = ADC.new(26).read_voltage
v27 = ADC.new(27).read_voltage
g2 = GPIO.new(2, GPIO::IN | GPIO::PULL_UP).read
g3 = GPIO.new(3, GPIO::IN | GPIO::PULL_UP).read
puts "   3V3 → GPIO26: #{v26.round(2)}V #{(3.1..3.45).include?(v26) ? 'OK' : 'NG'}（期待 3.3）"
puts "   5V 分圧 → GPIO27: #{v27.round(2)}V #{(2.3..2.7).include?(v27) ? 'OK' : 'NG'}（期待 2.5）"
puts "   GND → GPIO2: #{g2} #{g2 == 0 ? 'OK' : 'NG'} / GND → GPIO3: #{g3} #{g3 == 0 ? 'OK' : 'NG'}"
puts "   残りの GND ピンは、ジャンパを差し替えて同じ手順で（または GND どうしをテスターで）"
puts "== おわり"
