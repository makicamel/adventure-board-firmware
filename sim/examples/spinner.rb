# 何も押さなくても勝手に動く。
#
# 実機と同じ書き方。while true で回して sleep_ms で待つ。
# ブラウザではこのコードが専用のタスクで走り、sleep_ms のあいだ
# 画面に制御が戻るので固まらない。基板でもそのまま動く。
t = 0

while true
  t += 1
  matrix.clear

  # 外周を 1 周する点。
  i = t % 60
  if i < 16
    matrix.set(i + 1, 1)
  elsif i < 30
    matrix.set(16, i - 14)
  elsif i < 45
    matrix.set(16 - (i - 30), 16)
  else
    matrix.set(1, 16 - (i - 45))
  end

  # 中央に経過を示すバー。
  w = (t % 16) + 1
  x = 1
  while x <= w
    matrix.set(x, 8, 0x30)
    x += 1
  end

  matrix.show
  sleep_ms 80
end
