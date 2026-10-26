module LinkPong
  class Paddle
    ON          = 0x40
    OFF         = 0
    HALF_LENGTH = 1

    def initialize(court, x, middle)
      @court = court
      @x = x
      @middle = middle
      draw(ON)
    end

    def covers?(y)
      @middle - HALF_LENGTH <= y && y <= @middle + HALF_LENGTH
    end

    def move(dy)
      middle = clamp(@middle + dy)
      return if middle == @middle
      draw(OFF)
      @middle = middle
      draw(ON)
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

  class AutoPaddle < Paddle
    FRAMES_PER_DOT = 2

    def initialize(court, x, middle, frames_per_dot: FRAMES_PER_DOT)
      super(court, x, middle)
      @frames_per_dot = frames_per_dot
      @waypoints = []
      @frames = 0
    end

    def head_for(y)
      target = clamp(y)
      overshoot = @middle < target ? target + 1 : target - 1
      @waypoints = reachable?(overshoot) ? [overshoot, target] : [target]
      @frames = 0
    end

    def tick
      @frames += 1
      return if @waypoints.empty? || @frames % @frames_per_dot != 0
      goal = @waypoints[0]
      move(goal < @middle ? -1 : 1) unless goal == @middle
      @waypoints.shift if @middle == goal
    end
  end
end
