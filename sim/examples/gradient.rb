# 左から右へ暗→明のグラデーション。PWM がそのまま明るさに効く。
matrix.clear
y = 1
while y <= 16
  x = 1
  while x <= 16
    matrix.set(x, y, x * 16 - 1)
    x += 1
  end
  y += 1
end
matrix.show
