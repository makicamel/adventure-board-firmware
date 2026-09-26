# What is plugged into the breadboard, and what that does to the pins on J1.
#
# Holes are named the way the real board's print names them: a row letter
# and a column number, a1 .. j17. a-e are one side of the groove and f-j the
# other; the five holes of a column on one side are one strip, joined inside.
# J1's sockets are J1-1 .. J1-20 (see BoardLayout::J1_PINS for what each is).
#
# A circuit is saved and restored as text, one part per line:
#
#   wire J1-5 a3        a jumper wire
#   resistor b3 b7      1 kOhm
#   led c7 c9           anode (the long leg) first
#   switch e11          a tact switch straddling the groove: legs e11 e13 f11 f13
#
# The GPIO stand-in asks this class what a J1 pin reads, and tells it when a
# J1 pin is driven, so that code written for the board sees the circuit.
class Breadboard
  ROWS = "abcdefghij"
  COLUMNS = 17
  RESISTOR_OHMS = 1000

  # Supplies on J1, and what a GPIO output looks like from its pin. The RP2350
  # drives its pins through a few tens of ohms and is rated for 12 mA.
  V33_OHMS = 0.1
  V33_LIMIT_A = 0.3
  V5_OHMS = 0.2
  V5_LIMIT_A = 0.5
  GPIO_OHMS = 50
  GPIO_LIMIT_A = 0.012
  PULL_OHMS = 50_000
  GPIO_HIGH_V = 1.65   # reads high at or above this
  GPIO_MAX_V = 3.6     # more than this on a pin damages it

  # The current at which a red LED counts as fully lit. The kit's 1 kOhm gives
  # about 1.4 mA, so a quarter or so; brightness is linear in current.
  LED_FULL_A = 0.005

  KINDS = %w[wire resistor led switch]

  class << self
    # The breadboard the page shows and the GPIO stand-in reads.
    def current
      @current ||= attach(Breadboard.new)
    end

    def current=(board)
      @current = attach(board)
    end

    # A J1 input whose reading changes delivers an edge, as the button pins
    # do, so GPIO#irq works on breadboard switches too.
    def attach(board)
      if Object.const_defined?(:GPIO)
        board.on_edge do |pin, value|
          GPIO.fire(pin, value == 0 ? GPIO::EDGE_FALL : GPIO::EDGE_RISE)
        end
      end
      board
    end
  end

  attr_reader :parts, :warnings

  def initialize
    @parts = []          # [id, kind, legs]
    @next_id = 1
    @pressed = {}        # switch id => true
    @outputs = {}        # GPIO number => 0 / 1, while it is an output
    @pulls = {}          # GPIO number => :up / :down, while it is an input
    @readings = {}       # GPIO number => last value seen, for edges
    @solved = nil
    @warnings = []
    @listeners = []
  end

  # --- holes ---------------------------------------------------------------

  # "c7" => [2, 7], "J1-5" => [:j1, 5]; nil for anything else.
  def self.parse_hole(name)
    name = name.to_s
    if name.start_with?("J1-")
      n = name[3, name.size - 3].to_i
      return (1 <= n && n <= 20) ? [:j1, n] : nil
    end
    row = ROWS.index(name[0, 1])
    col = name[1, name.size - 1].to_i
    return nil if row.nil? || col < 1 || COLUMNS < col
    return nil unless col.to_s == name[1, name.size - 1]
    [row, col]
  end

  def self.hole_name(row, col)
    "#{ROWS[row]}#{col}"
  end

  # The point in the circuit a hole belongs to: its strip, or what J1 wires
  # the socket to.
  def self.node_of(name)
    h = parse_hole(name)
    return nil unless h
    return BoardLayout::J1_PINS[h[1]][2] if h[0] == :j1   # "GND", "3V3", "GPIO2" ...
    "#{h[0] < 5 ? 'top' : 'bottom'}#{h[1]}"
  end

  # --- parts ---------------------------------------------------------------

  # Returns the new part's id, or a message saying why it does not fit.
  def place(kind, legs)
    kind = kind.to_s
    return "#{kind} という部品はありません" unless KINDS.include?(kind)
    legs = switch_legs(legs[0]) if kind == "switch"
    return "スイッチは e か f の段に、右に 2 列の空きを取って置きます" if legs.nil?
    return "足が 2 本要ります" unless legs.size == 2 || kind == "switch"
    i = 0
    while i < legs.size
      return "#{legs[i]} という穴はありません" unless Breadboard.parse_hole(legs[i])
      return "#{legs[i]} にはもう挿さっています" if occupied?(legs[i])
      i += 1
    end
    return "同じ穴に両方の足は挿せません" if legs[0] == legs[1]
    id = @next_id
    @next_id += 1
    @parts << [id, kind, legs]
    changed
    id
  end

  def remove(id)
    i = 0
    while i < @parts.size
      if @parts[i][0] == id
        @parts.delete_at(i)
        @pressed.delete(id)
        changed
        return true
      end
      i += 1
    end
    false
  end

  def clear
    @parts = []
    @pressed = {}
    changed
  end

  def part(id)
    i = 0
    while i < @parts.size
      return @parts[i] if @parts[i][0] == id
      i += 1
    end
    nil
  end

  def occupied?(hole)
    i = 0
    while i < @parts.size
      return true if @parts[i][2].include?(hole)
      i += 1
    end
    false
  end

  def press(id)
    return if @pressed[id]
    @pressed[id] = true
    changed
  end

  def release(id)
    return unless @pressed[id]
    @pressed.delete(id)
    changed
  end

  def pressed?(id)
    @pressed[id] == true
  end

  # --- text ----------------------------------------------------------------

  def to_text
    out = ""
    i = 0
    while i < @parts.size
      p = @parts[i]
      legs = p[1] == "switch" ? [p[2][0]] : p[2]
      out << p[1] << " " << legs.join(" ") << "\n"
      i += 1
    end
    out
  end

  # Replaces what is plugged in. Returns the messages for lines that did not
  # fit (the rest are placed).
  def load_text(text)
    @parts = []
    @pressed = {}
    errors = []
    lines = text.to_s.split("\n")
    i = 0
    while i < lines.size
      line = lines[i].strip
      i += 1
      next if line.empty? || line.start_with?("#")
      words = line.split(" ")
      result = place(words[0], words[1, words.size - 1])
      errors << "#{i} 行目: #{result}" if result.is_a?(String)
    end
    changed
    errors
  end

  # The wiring a program asks for in its comments, as text for load_text; nil
  # when it has none. A comment line is taken when it starts with a part's
  # name followed by its holes, and whatever comes after them is a note:
  #
  #   #   led c7 c9           赤 LED。長い足を c7
  #
  # On the board these are only comments, so the same file is the program
  # and the instructions for wiring it.
  def self.wiring_in(source)
    out = ""
    lines = source.to_s.split("\n")
    i = 0
    while i < lines.size
      line = lines[i].strip
      i += 1
      next unless line.start_with?("#")
      words = line[1, line.size - 1].to_s.split(" ")
      next if words.empty? || !KINDS.include?(words[0])
      want = words[0] == "switch" ? 1 : 2
      holes = []
      j = 1
      while j < words.size && holes.size < want && parse_hole(words[j])
        holes << words[j]
        j += 1
      end
      out << words[0] << " " << holes.join(" ") << "\n" if holes.size == want
    end
    out.empty? ? nil : out
  end

  # --- what the pins see ---------------------------------------------------

  # The GPIO stand-in reports how each pin is set up. Pins not on J1, or on
  # J1 but with nothing plugged into their socket, are left alone.
  def gpio_output(pin, value)
    @pulls.delete(pin)
    return if @outputs[pin] == value
    @outputs[pin] = value
    changed if uses_gpio?(pin)
  end

  def gpio_input(pin, pull)
    had = @outputs.delete(pin)
    return if had.nil? && @pulls[pin] == pull
    if pull
      @pulls[pin] = pull
    else
      @pulls.delete(pin)
    end
    changed if uses_gpio?(pin)
  end

  # Forget how the pins were set up, as the chip does on reset. What is
  # plugged in stays.
  def reset_pins
    @outputs = {}
    @pulls = {}
    @readings = {}
    changed
  end

  # Whether something plugged in reaches this GPIO's socket.
  def uses_gpio?(pin)
    solution
    @touched[find("GPIO#{pin}")] == true
  end

  # 0 or 1 as the pin would read it; nil when the breadboard has nothing to do
  # with the pin. A pin nothing drives floats and reads at random.
  def gpio_read(pin)
    return nil unless uses_gpio?(pin)
    c = solution
    node = "GPIO#{pin}"
    node = find(node)
    return random_bit unless c.driven?(node)
    c.voltage(node) >= GPIO_HIGH_V ? 1 : 0
  end

  # Called with (pin, value) whenever a J1 input's reading changes, which is
  # what the GPIO stand-in turns into edge interrupts.
  def on_edge(&block)
    @listeners << block
  end

  # --- results -------------------------------------------------------------

  # 0.0 .. 1.0, linear in current.
  def led_brightness(id)
    a = led_current(id)
    return 0.0 if a.nil? || a <= 0
    b = a / LED_FULL_A
    b > 1.0 ? 1.0 : b
  end

  def led_current(id)
    solution.current(id)
  end

  def voltage_at(hole)
    node = Breadboard.node_of(hole)
    return nil if node.nil?
    c = solution
    c.voltage(find(node))
  end

  # The point a hole's node ended up as once wires are merged ("GPIO3" may
  # be one strip with "top11").
  def node_for(name)
    solution
    find(name)
  end

  # The solved circuit for what is plugged in now.
  def solution
    return @solved if @solved
    build
    @solved
  end

  private

  def switch_legs(anchor)
    h = Breadboard.parse_hole(anchor)
    return nil if h.nil? || h[0] == :j1 || h[0] != 4 || COLUMNS < h[1] + 2
    [Breadboard.hole_name(4, h[1]), Breadboard.hole_name(4, h[1] + 2),
     Breadboard.hole_name(5, h[1]), Breadboard.hole_name(5, h[1] + 2)]
  end

  def changed
    @solved = nil
    solution
    report_edges
  end

  # Wires join points outright, so they are merged before solving rather than
  # being solved as tiny resistors.
  def find(node)
    while (up = @joined[node]) && up != node
      node = up
    end
    node
  end

  def join(a, b)
    ra = find(a)
    rb = find(b)
    @joined[rb] = ra unless ra == rb
  end

  # J1's GND, 3V3 and 5V are ordinary points held at their voltage through a
  # small resistance, like a GPIO output. A short between two of them, or a
  # pin driving against one, is then just a large current the solver reports.
  def build
    @joined = {}
    c = Circuit.new
    parts = @parts
    i = 0
    while i < parts.size
      p = parts[i]
      legs = p[2]
      if p[1] == "wire"
        join(Breadboard.node_of(legs[0]), Breadboard.node_of(legs[1]))
      elsif p[1] == "switch"
        # The two legs across the groove are always joined; pressing joins
        # the left pair to the right pair.
        join(Breadboard.node_of(legs[0]), Breadboard.node_of(legs[2]))
        join(Breadboard.node_of(legs[1]), Breadboard.node_of(legs[3]))
      end
      i += 1
    end
    @touched = {}
    i = 0
    while i < parts.size
      p = parts[i]
      legs = p[2]
      j = 0
      while j < legs.size
        @touched[find(Breadboard.node_of(legs[j]))] = true
        j += 1
      end
      if p[1] == "resistor" || p[1] == "led" || p[1] == "switch"
        a = find(Breadboard.node_of(legs[0]))
        b = find(Breadboard.node_of(legs[1]))
        if p[1] == "resistor"
          c.resistor(a, b, RESISTOR_OHMS, p[0])
        elsif p[1] == "led"
          c.led(a, b, p[0])
        else
          c.switch(a, b, @pressed[p[0]] == true, p[0])
        end
      end
      i += 1
    end
    # Ground's own limit is out of reach: whatever flows into it has come out
    # of something else, and that is the one worth naming.
    add_supply(c, "GND", 0.0, V33_OHMS, 1.0e9)
    add_supply(c, "3V3", 3.3, V33_OHMS, V33_LIMIT_A)
    add_supply(c, "5V", 5.0, V5_OHMS, V5_LIMIT_A)
    @gpio_nodes = []
    pins = gpio_pins
    i = 0
    while i < pins.size
      pin = pins[i]
      name = "GPIO#{pin}"
      node = find(name)
      i += 1
      next unless @touched[node]
      @gpio_nodes << name
      value = @outputs[pin]
      if !value.nil?
        c.source(node, value == 0 ? 0.0 : 3.3, GPIO_OHMS, GPIO_LIMIT_A, name)
      elsif @pulls[pin] == :up
        c.source(node, 3.3, PULL_OHMS, 1.0e9, "#{name} pull-up")
      elsif @pulls[pin] == :down
        c.source(node, 0.0, PULL_OHMS, 1.0e9, "#{name} pull-down")
      end
    end
    # The circuit's own ground is the reference the supplies sit on; nothing
    # on the breadboard reaches it except through them.
    @solved = c.solve
    @warnings = describe(c)
  end

  def add_supply(c, name, volts, ohms, limit)
    node = find(name)
    c.source(node, volts, ohms, limit, name) if @touched[node]
  end

  def gpio_pins
    out = []
    pins = BoardLayout::J1_PINS
    n = 1
    while n <= 20
      net = pins[n][2]
      out << net[4, net.size - 4].to_i if net.start_with?("GPIO")
      n += 1
    end
    out
  end

  def report_edges
    pins = gpio_pins
    i = 0
    while i < pins.size
      pin = pins[i]
      i += 1
      next unless @outputs[pin].nil?
      value = nil
      if uses_gpio?(pin)
        node = find("GPIO#{pin}")
        c = @solved
        value = c.voltage(node) >= GPIO_HIGH_V ? 1 : 0 if c.driven?(node)
      end
      before = @readings[pin]
      @readings[pin] = value
      next if value.nil? || before.nil? || before == value
      j = 0
      while j < @listeners.size
        @listeners[j].call(pin, value)
        j += 1
      end
    end
  end

  def describe(c)
    out = []
    list = c.warnings
    i = 0
    while i < list.size
      w = list[i]
      ma = (w[2].abs * 1000.0).round(1)
      if w[0] == :led_overcurrent
        out << "LED に #{ma} mA 流れています。抵抗を入れないと壊れます"
      elsif w[1] == "3V3" || w[1] == "5V"
        out << "#{w[1]} から #{ma} mA 流れています。GND とつながっていませんか"
      else
        out << "#{w[1]} に #{ma} mA 流れています（12 mA まで）。抵抗を入れてください"
      end
      i += 1
    end
    nodes = @gpio_nodes
    i = 0
    while i < nodes.size
      v = c.voltage(find(nodes[i]))
      if GPIO_MAX_V < v
        out << "#{nodes[i]} に #{v.round(1)} V かかっています。GPIO は 3.3 V までです"
      end
      i += 1
    end
    out
  end

  def random_bit
    @seed = ((@seed || 12345) * 1103515245 + 12345) % 2147483648
    (@seed >> 16) & 1
  end
end
