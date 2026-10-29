module LinkPong
  # 役割（自分の TX を白と黄のどちらにするか）は相手の線を読んで決める。先につないだ相手は、TX を High にして待っている
  # 役割は最初の 1 回だけ決める
  class Link
    MAX_RANDOM_DELAY_MS = 300            # 2 枚がほぼ同時に選んでも、両方が同じ役割にならないように

    def initialize
      sleep_ms rand(MAX_RANDOM_DELAY_MS)
      @role = high?(Board::GROVE_B_TX_PIN) ? :b : :a
      @grove = AdventureBoard.grove_link(role: @role)
    end

    def role_a? = @role == :a

    def flush = @grove.flush_input

    # 先頭の改行で、相手が UART を開いたときに届くゴミを別の行に切り離す
    def write(*words)
      @grove.puts("\n" + words.join(" "))
    end

    def read
      line = @grove.gets
      line && line.split(" ")
    end

    private

    def high?(pin)
      gpio = GPIO.new(pin, GPIO::IN | GPIO::PULL_DOWN)
      sleep_ms 5
      gpio.read == 1
    end
  end

  # 右の基板用。Match は自分が左にいる前提で描くので、左右を反転する
  class MirroredMatrix
    def initialize(matrix)
      @matrix = matrix
    end

    def set(x, y, brightness)
      @matrix.set(LedMatrix::WIDTH + 1 - x, y, brightness)
    end

    def clear = @matrix.clear

    def show = @matrix.show
  end
end
