# 基板 2 枚の GROVE リンク（grove_link_chat.rb）の切り分け。2 枚の J5 をふつうの Grove ケーブルでつなぎ、
# 1 枚目は ROLE = :a、2 枚目は ROLE = :b に書き換えて走らせる（どちらも「実機を再起動」してから）。
#   1. リンクを開く前に、GPIO28 / 29 をプルダウンとプルアップで読む（相手の TX が来ていれば、プルダウンでも 1）
#   2. リンクを開き、30 秒のあいだ 1 秒ごとに 1 行送り、届いたバイトをそのまま表示する
require 'adventure_board'
GC.start

ROLE = :a   # もう 1 枚では :b

def level(pin, pull)
  g = GPIO.new(pin, GPIO::IN | pull)
  sleep_ms 5
  g.read
end

[28, 29].each do |pin|
  puts "GPIO#{pin}: pull-down #{level(pin, GPIO::PULL_DOWN)} / pull-up #{level(pin, GPIO::PULL_UP)}"
end
puts "(相手が先に走っていれば、:a は GPIO29、:b は GPIO28 がプルダウンでも 1 になるはず)"

link = AdventureBoard.grove_link(role: ROLE)
puts "role #{ROLE}: link open"

n = 0
last = Machine.uptime_us
while n < 30
  now = Machine.uptime_us
  if 1_000_000 <= now - last
    last = now
    n += 1
    link.puts("#{ROLE}#{n}")
    puts "sent #{ROLE}#{n}"
  end
  raw = link.uart.read
  p raw if raw && 0 < raw.size
  puts "lost #{link.lost}" if 0 < link.lost
  sleep_ms 20
end
puts "done"
