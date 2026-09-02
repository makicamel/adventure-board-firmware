# The green LED beside the USB connector.
#
# GPIO16 through R31 into the anode, cathode to ground, so a high output lights
# it. The red LED next to it is wired straight to 3V3 and is not controllable —
# it says the board has power, nothing more.
#
# GPIO16 is also PWM0A, so this could be dimmed; it is plain on and off here
# because that is what a status light is for.
class StatusLed
  def initialize(pin: Board::STATUS_LED_PIN)
    @gpio = GPIO.new(pin, GPIO::OUT)
    @on = false
    off
  end

  def on
    @gpio.write(1)
    @on = true
    self
  end

  def off
    @gpio.write(0)
    @on = false
    self
  end

  def on?
    @on
  end

  def toggle
    @on ? off : on
  end

  def write(value)
    (value == 0 || value == false) ? off : on
  end
end
