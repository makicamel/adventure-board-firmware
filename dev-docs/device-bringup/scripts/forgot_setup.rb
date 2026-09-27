# よくある間違い: LED ドライバに電流と倍率を設定し忘れると、1 個も光らない。
# 試したあとは「シミュレータをリセット」を押す（実機なら再起動する）。

require 'adventure_board/led_matrix'   # LED マトリクス
GC.start                               # 読み込みで使ったメモリを片付ける

led = IS31FL3729.new(i2c: AdventureBoard.board.i2c, address: LedMatrix::TOP_ADDRESS)   # 上半分のドライバを直接触る
led.reset        # チップを電源投入時の状態に戻す（電流も倍率も 0 になる）
led.configure    # 動作モードの設定
led.fill(0xFF)   # 全部の LED を最大の明るさに
led.flush        # チップへ送る
# ここまでで真っ暗。下の 2 行のコメントを外すと光る。
# led.global_current = 0x20   # 全体の電流
# led.scaling_all = 0xFF      # LED ごとの倍率
