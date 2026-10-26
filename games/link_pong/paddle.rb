module LinkPong
  class Paddle
    ON             = 0xFF
    OFF            = 0
    HALF_LENGTH    = 1
    FRAMES_PER_DOT = 2

    def initialize(court, x, middle)
      @court = court
      @x = x
      @middle = middle
      @waypoints = []
      @frames = 0
      draw(ON)
    end

    def head_for(y)
      target = clamp(y)
      overshoot = @middle < target ? target + 1 : target - 1
      @waypoints = reachable?(overshoot) ? [overshoot, target] : [target]
      @frames = 0
    end

    def covers?(y)
      @middle - HALF_LENGTH <= y && y <= @middle + HALF_LENGTH
    end

    def tick
      @frames += 1
      return if @waypoints.empty? || @frames % FRAMES_PER_DOT != 0
      goal = @waypoints[0]
      unless goal == @middle
        draw(OFF)
        @middle += goal < @middle ? -1 : 1
        draw(ON)
      end
      @waypoints.shift if @middle == goal
    end

    private

    def draw(brightness)
      y = @middle - HALF_LENGTH
      while y <= @middle + HALF_LENGTH
        @court.set(@x, y, brightness)
        y += 1
      end
    end

    def clamp(middle)
      if middle < highest_middle
        highest_middle
      elsif lowest_middle < middle
        lowest_middle
      else
        middle
      end
    end

    def highest_middle = @court.top + HALF_LENGTH

    def lowest_middle = @court.bottom - HALF_LENGTH

    def reachable?(middle)
      highest_middle <= middle && middle <= lowest_middle
    end
  end
end
