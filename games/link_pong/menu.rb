module LinkPong
  class Menu
    CHOSEN         = 0x40
    UNCHOSEN       = 0x18
    LEFT_OPTION_X  = 2
    RIGHT_OPTION_X = Court::NET_X + 1
    OPTION_WIDTH   = 7
    PLAYERS_TOP    = 3
    LEVEL_TOP      = 10

    attr_reader :players

    def initialize(matrix, buttons)
      @matrix = matrix
      @buttons = buttons
      @players = 1
      @hard = false
      @on_players = true
    end

    def hard? = @hard

    def run
      @buttons.clear_presses
      draw
      while true
        button = @buttons.take_press
        if button == :up || button == :down
          @on_players = !@on_players
          draw
        elsif button == :left || button == :right
          if @on_players
            @players = button == :left ? 1 : 2
          else
            @hard = button == :right
          end
          draw
        elsif button
          return
        end
        sleep_ms 10
      end
    end

    private

    def draw
      @matrix.clear
      draw_option("1P", LEFT_OPTION_X, PLAYERS_TOP, @players == 1, @on_players)
      draw_option("2P", RIGHT_OPTION_X, PLAYERS_TOP, @players == 2, @on_players)
      draw_option("N", LEFT_OPTION_X, LEVEL_TOP, !@hard, !@on_players)
      draw_option("H", RIGHT_OPTION_X, LEVEL_TOP, @hard, !@on_players)
      @matrix.show
    end

    def draw_option(text, left, top, chosen, on_this_row)
      width = Font.width(text)
      x = left + (OPTION_WIDTH - width) / 2
      Font.draw(@matrix, text, x, top, chosen ? CHOSEN : UNCHOSEN)
      draw_underline(x, top + Font::HEIGHT + 1, width) if chosen && on_this_row
    end

    def draw_underline(left, y, width)
      width.times { |i| @matrix.set(left + i, y, CHOSEN) }
    end
  end
end
