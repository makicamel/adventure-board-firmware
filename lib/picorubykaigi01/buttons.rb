# The six buttons.
#
# Edge interrupts rather than polling. A press is an event, so it cannot be
# missed however short the click is or however slowly the main loop runs — the
# level alone would lose a tap that started and finished between two polls.
# picoruby-irq debounces in the gem, so there is nothing to filter here.
#
# Presses queue up and are taken one at a time; the level is there separately
# for anything that should act while a button is held. Auto-repeat is not here
# on purpose: a loop that wants it can count its own ticks against `pressed?`,
# and one that does not is not paying for it.
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
    @level = 0
    @queue = []
    i = 0
    while i < pins.size
      name = pins[i][0]
      gpio = GPIO.new(pins[i][1], GPIO::IN | GPIO::PULL_UP)
      @names << name
      @gpios << gpio
      watch(gpio, name, 1 << i, debounce)
      i += 1
    end
  end

  # Currently held down.
  def pressed?(name)
    (@level & mask_of(name)) != 0
  end

  def any?
    @level != 0
  end

  # The names currently held down.
  def pressed
    out = []
    names = @names
    i = 0
    while i < names.size
      out << names[i] if (@level & (1 << i)) != 0
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
  def watch(gpio, name, mask, debounce)
    gpio.irq(GPIO::EDGE_FALL | GPIO::EDGE_RISE, debounce: debounce) do |_peripheral, event_type|
      if event_type == GPIO::EDGE_RISE
        @level &= ~mask
      else
        @level |= mask
        push(name)
      end
    end
    nil
  end

  def push(name)
    queue = @queue
    queue << name
    queue.shift while QUEUE_LIMIT < queue.size
    nil
  end

  def mask_of(name)
    names = @names
    i = 0
    while i < names.size
      return 1 << i if names[i] == name
      i += 1
    end
    0
  end
end
