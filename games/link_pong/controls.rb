module LinkPong
  module Controls
    HELD_DOTS = 2 # 上下を押し続けたとき 1 フレームに動くドット数

    private

    # 短く押したキーを取りこぼさないよう、押した回数（each_press）を先に見る
    def player_direction
      pressed_dx = 0
      pressed_dy = 0
      @buttons.each_press do |name|
        pressed_dx = -1 if name == :left
        pressed_dx = 1 if name == :right
        pressed_dy = -1 if name == :up
        pressed_dy = 1 if name == :down
      end
      dx = pressed_dx == 0 ? held_direction(:left, :right) : pressed_dx
      dy = pressed_dy == 0 ? held_direction(:up, :down) * HELD_DOTS : pressed_dy
      [dx, dy]
    end

    def held_direction(minus, plus)
      if @buttons.pressed?(minus)
        -1
      elsif @buttons.pressed?(plus)
        1
      else
        0
      end
    end
  end
end
