# The six buttons.
#
# Edge interrupts rather than polling. A press is an event, so it cannot be
# missed however short the click is or however slowly the main loop runs — the
# level alone would lose a tap that started and finished between two polls.
# picoruby-irq debounces in the gem, so there is nothing to filter here, and
# only the falling edge is asked for: a press is all that gets queued. (Before
# the gem watched both edges itself, the bounce of a release came through as a
# second press; see dev-docs/upstream-issues.md.)
#
# Presses queue up and are taken one at a time. Whether a button is held is
# read off the pin rather than tracked from edges, so it is right whenever it is
# asked, bounce or not. Auto-repeat is not here on purpose: a loop that wants it
# can count its own ticks against `pressed?`, and one that does not is not
# paying for it.
class Buttons
  NAMES = [:up, :down, :left, :right, :a, :b]

  # Milliseconds, handled inside picoruby-irq.
  DEFAULT_DEBOUNCE_MS = 20

  # Presses beyond this are dropped rather than growing without bound; a loop
  # that far behind has bigger problems than a lost keystroke.
  QUEUE_LIMIT = 16

  def initialize(pins: Board::BUTTON_PINS, debounce: DEFAULT_DEBOUNCE_MS)
    @names = []
    @gpios = []
    @queue = []
    i = 0
    while i < pins.size
      name = pins[i][0]
      gpio = GPIO.new(pins[i][1], GPIO::IN | GPIO::PULL_UP)
      @names << name
      @gpios << gpio
      watch(gpio, name, debounce)
      i += 1
    end
  end

  # Currently held down. Active low.
  def pressed?(name)
    names = @names
    i = 0
    while i < names.size
      return @gpios[i].read == 0 if names[i] == name
      i += 1
    end
    false
  end

  def any?
    gpios = @gpios
    i = 0
    while i < gpios.size
      return true if gpios[i].read == 0
      i += 1
    end
    false
  end

  # The names currently held down.
  def pressed
    out = []
    names = @names
    gpios = @gpios
    i = 0
    while i < names.size
      out << names[i] if gpios[i].read == 0
      i += 1
    end
    out
  end

  # The oldest press not yet taken, or nil. Every press is delivered exactly
  # once, which is the whole point of queueing them.
  def take_press
    @queue.shift
  end

  def each_press
    while (name = @queue.shift)
      yield name
    end
    nil
  end

  def presses_waiting
    @queue.size
  end

  def clear_presses
    @queue = []
    nil
  end

  private

  # A method, not the body of the loop above: `while` opens no scope, so a
  # block written inside one closes over the shared variables and every button
  # would end up reporting the last one.
  def watch(gpio, name, debounce)
    gpio.irq(GPIO::EDGE_FALL, debounce: debounce) do |_peripheral, _event_type|
      push(name)
    end
    nil
  end

  def push(name)
    queue = @queue
    queue << name
    queue.shift while QUEUE_LIMIT < queue.size
    nil
  end
end
