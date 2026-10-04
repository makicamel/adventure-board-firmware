# GROVE2（J5）の疎通確認。Grove → ジャンパ変換ケーブル（オスのピン）で J5 をブレッドボードに出して使う。
#   ケーブルの色: 黄 = GPIO29 / 白 = GPIO28 / 赤 = 電源 / 黒 = GND（PV1 / 量産版）
#   1 段階目: ケーブルなし。GPIO28 / 29 が GND・電源・互いに短絡していないか
#   2 段階目: 黄と白をつなぐ。両方向に High / Low が届くか（色とピンの対応もここで分かる）
#   3 段階目: 電源と GND。赤 → 抵抗 → 黄 → 抵抗 → 黒 で半分にして ADC で測る。白 → 黒
#   4 段階目: 黄と白をつなぎ直し、PIO の UART で 0〜255 の全バイトを折り返す
# 段階の切り替えは基板の A ボタン（GPIO22）。出力欄の指示どおりにつないでから A を押す。
#
# ⚠ 赤（電源）を GPIO に直接つながない。基板の 0Ω 抵抗で 3.3V / 5V を選ぶ作りで、5V のこともある
#   （量産版の部品表では GROVE2 は 3.3V、GROVE1 は 5V）。抵抗は同じ値を 2 本（1kΩ でも 10kΩ でもよい）。
# ⚠ ハードウェアの UART0 は使わない。R2P2 のコンソール（R2P2_CONSOLE_UART=1）が UART0 を GPIO0 / 1 で使っている。
require 'gpio'
require 'adc'
require 'uart'

YELLOW = 29
WHITE = 28
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

def read_with(pin, pull)
  g = GPIO.new(pin, GPIO::IN | pull)
  sleep_ms 5
  g.read
end

# o_pin を High / Low にして、i_pin（プルダウン）で読む。届けば [1, 0]
def drive(o_pin, i_pin)
  i = GPIO.new(i_pin, GPIO::IN | GPIO::PULL_DOWN)
  o = GPIO.new(o_pin, GPIO::OUT)
  o.write(1); sleep_ms 2; r1 = i.read
  o.write(0); sleep_ms 2; r0 = i.read
  GPIO.new(o_pin, GPIO::IN | GPIO::PULL_DOWN)
  [r1, r0]
end

def name(pin)
  pin == YELLOW ? "黄(GPIO29)" : "白(GPIO28)"
end

# --- 1. ケーブルなし ------------------------------------------------------
puts "== 1. GROVE2 に何も挿さないで A を押す"
wait_a("   （A を押すと開始）")
ng = 0
[YELLOW, WHITE].each do |p|
  up = read_with(p, GPIO::PULL_UP)
  down = read_with(p, GPIO::PULL_DOWN)
  if up != 1
    puts "   NG: #{name(p)} がプルアップしても Low（GND と短絡?）"
    ng += 1
  end
  if down != 0
    puts "   NG: #{name(p)} がプルダウンしても High（電源と短絡?）"
    ng += 1
  end
end
[[WHITE, YELLOW], [YELLOW, WHITE]].each do |o, i|
  r = drive(o, i)
  if r[0] == 1
    puts "   NG: #{name(o)} を High にすると #{name(i)} も High（2 本が短絡）"
    ng += 1
  end
end
puts "   1. #{ng == 0 ? 'OK: 短絡なし' : "NG #{ng} 件"}"

# --- 2. 黄と白をつなぐ -----------------------------------------------------
puts "== 2. ケーブルを GROVE2 に挿し、黄と白をつなぐ（ブレッドボードの同じ列に挿す）。赤と黒はどこにもつながない"
wait_a("   （つないだら A を押す）")
ng = 0
[[WHITE, YELLOW], [YELLOW, WHITE]].each do |o, i|
  r = drive(o, i)
  unless r == [1, 0]
    puts "   NG: #{name(o)} → #{name(i)}: High→#{r[0]} Low→#{r[1]}"
    ng += 1
  end
end
puts "   2. #{ng == 0 ? 'OK: 黄と白が GPIO29 と GPIO28 に届いている' : "NG #{ng} 件（色とピンの対応が違う、または断線）"}"

# --- 3. 電源と GND --------------------------------------------------------
puts "== 3. 黄と白を離して、次のようにつなぐ（ブレッドボードで）:"
puts "     赤 → 抵抗 → 黄、黄 → 抵抗 → 黒   （同じ値の抵抗 2 本で、電源を半分にして黄で測る）"
puts "     白 → 黒"
puts "     ⚠ 赤を黄や白に直接つながない"
wait_a("   （つないだら A を押す）")
v = ADC.new(YELLOW).read_voltage
supply = v * 2
kind = if (1.5..1.8).include?(v)
         "3.3V"
       elsif (2.3..2.7).include?(v)
         "5V"
       end
puts "   赤（電源）: 黄で #{v.round(2)}V → 電源はおよそ #{supply.round(2)}V #{kind ? "OK（#{kind}）" : 'NG（3.3V でも 5V でもない）'}"
g = read_with(WHITE, GPIO::PULL_UP)
puts "   黒（GND）→ 白: #{g} #{g == 0 ? 'OK' : 'NG（黒が GND につながっていない）'}"

# --- 4. UART で折り返す ---------------------------------------------------
puts "== 4. 抵抗と白 → 黒を外して、また黄と白をつなぐ"
wait_a("   （つないだら A を押す）")
uart = UART.new(unit: :PIO_UART0, txd_pin: WHITE, rxd_pin: YELLOW, baudrate: 115_200, rx_buffer_size: 1024)
uart.clear_rx_buffer
sent = ""
i = 0
while i < 256
  sent << i.chr
  i += 1
end
uart.write(sent)
sleep_ms 100                    # 256 バイトは 115200bps で約 22ms
got = uart.read.to_s
bad = 0
i = 0
while i < 256
  bad += 1 if got.getbyte(i) != i
  i += 1
end
if got.bytesize == 256 && bad == 0
  puts "   4. OK: 白(TX) → 黄(RX) で 256 バイトすべて届いた"
else
  puts "   4. NG: 届いたのは #{got.bytesize} バイト、違っていたのは #{bad} バイト"
end
puts "== おわり（PIO の UART が GPIO28 / 29 をつかんだままなので、ほかのプログラムの前に「実機を再起動」する）"
