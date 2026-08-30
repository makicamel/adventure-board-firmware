# よくある間違い: リセットと設定だけして、電流とスケーリングを書き忘れる。
#
# IS31FL3729 は電源投入時 GCC(0xA1) も Scaling(0x90-0x9F) も 0 なので、
# PWM をいくら書いても 1 個も光らない。実機で必ず一度はハマるところ。
led = IS31FL3729.new(i2c: board.i2c, address: LedMatrix::TOP_ADDRESS)
led.reset
led.configure
led.fill(0xFF)
led.flush
# ここまでで真っ暗。下の 2 行のコメントを外すと光る。
# led.global_current = 0x20
# led.scaling_all = 0xFF

# なお reset は本当にチップを初期状態へ戻すので、この後は
# matrix 側の上半分も光らなくなる（実機と同じ挙動）。
# Reset ボタンを押すと作り直されて元に戻る。
