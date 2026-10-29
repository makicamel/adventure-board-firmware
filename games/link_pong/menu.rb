module LinkPong
  class Menu
    CHOSEN           = 0x40
    UNCHOSEN         = 0x18
    LEFT_OPTION_X    = 2
    RIGHT_OPTION_X   = Court::NET_X + 1
    OPTION_WIDTH     = 7
    UPPER_OPTION_TOP = 3
    LOWER_OPTION_TOP = 10

    include Screen

    attr_reader :player_count

    def initialize(matrix, buttons)
      @matrix = matrix
      @buttons = buttons
      @player_count = 1
      @hard = false
      @left = true
      @on_players = true
    end

    def hard? = @hard

    def left? = @left

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
            @player_count = button == :left ? 1 : 2
          elsif @player_count == 1
            @hard = button == :right
          else
            @left = button == :left
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
      repaint do
        draw_option("1P", LEFT_OPTION_X, UPPER_OPTION_TOP, @player_count == 1, @on_players)
        draw_option("2P", RIGHT_OPTION_X, UPPER_OPTION_TOP, @player_count == 2, @on_players)
        if @player_count == 1
          draw_option("N", LEFT_OPTION_X, LOWER_OPTION_TOP, !@hard, !@on_players)
          draw_option("H", RIGHT_OPTION_X, LOWER_OPTION_TOP, @hard, !@on_players)
        else
          draw_option("L", LEFT_OPTION_X, LOWER_OPTION_TOP, @left, !@on_players)
          draw_option("R", RIGHT_OPTION_X, LOWER_OPTION_TOP, !@left, !@on_players)
        end
      end
    end

    def draw_option(text, left, top, chosen, on_this_row)
      width = Font.width(text)
      x = left + (OPTION_WIDTH - width) / 2
      draw_text(text, x, top, chosen ? CHOSEN : UNCHOSEN)
      draw_underline(x, top + Font::HEIGHT + 1, width) if chosen && on_this_row
    end

    def draw_underline(left, y, width)
      width.times { |i| @matrix.set(left + i, y, CHOSEN) }
    end
  end
end
