# The breadboard's circuit, solved for the voltage at every point and the
# current through every part. Only what the kit and the simulator offer:
# resistors, blue LEDs, tact switches, and the pins that drive them (supply
# rails and GPIO outputs, each a voltage behind a small resistance).
#
# Nodal analysis: each point's voltage is an unknown, Kirchhoff's current law
# at each point is one equation. The LED is not linear, so it is replaced by
# the straight line that touches its curve at the current guess, and the
# system is solved again from the new voltages until they stop moving.
#
# Points are whatever the caller names them (the breadboard uses its strips);
# :gnd is 0 V and is not an unknown. Units are volts, ohms and amperes.
class Circuit
  # Blue LED: 2.70 V at 1 mA and 3.0 V at 20 mA, which is what a common
  # 3 mm / 5 mm blue part does. From a 3.3 V pin that leaves little for the
  # resistor, so currents are small -- and a blue LED is bright at them.
  LED_ON_V = 2.70
  LED_NVT = 0.30 / Math.log(20.0)
  LED_IS = 1.0e-3 / Math.exp(LED_ON_V / LED_NVT)
  LED_MAX_A = 0.020
  # A closed switch's contact.
  SWITCH_OHMS = 0.05
  # Keeps a point that nothing drives from making the equations unsolvable.
  # Far too weak to matter anywhere else.
  GMIN = 1.0e-9
  MAX_ITERATIONS = 200
  TOLERANCE_V = 1.0e-7
  # A diode's voltage may move this much per step. Without it the first steps
  # overshoot into exp() of tens and never come back.
  LED_STEP_V = 0.1

  attr_reader :warnings

  def initialize
    @resistors = []   # [a, b, ohms, name]
    @leds = []        # [anode, cathode, name]
    @sources = []     # [node, volts, ohms, limit_a, name]
    @volts = {}
    @led_v = []
    @warnings = []
  end

  def resistor(a, b, ohms, name = nil)
    @resistors << [a, b, ohms.to_f, name]
    self
  end

  def switch(a, b, closed, name = nil)
    @resistors << [a, b, SWITCH_OHMS, name] if closed
    self
  end

  def led(anode, cathode, name = nil)
    @leds << [anode, cathode, name]
    self
  end

  # A voltage behind a resistance: a supply rail, or a GPIO driving its pin.
  # limit_a is how much it may give or take before it is being hurt.
  def source(node, volts, ohms, limit_a, name = nil)
    @sources << [node, volts.to_f, ohms.to_f, limit_a.to_f, name]
    self
  end

  def voltage(node)
    return 0.0 if node == :gnd
    v = @volts[node]
    v.nil? ? 0.0 : v
  end

  # Whether anything sets this point's voltage: a path through parts to a
  # source or to ground. A pin on a point that nothing drives is floating and
  # reads whatever it likes.
  def driven?(node)
    return true if node == :gnd
    @driven ? @driven[node] == true : false
  end

  # Current from a to b through the named resistor or switch, anode to cathode
  # through the named LED, and out of the named source into its point.
  def current(name)
    list = @resistors
    i = 0
    while i < list.size
      r = list[i]
      return (voltage(r[0]) - voltage(r[1])) / r[2] if r[3] == name
      i += 1
    end
    list = @leds
    i = 0
    while i < list.size
      d = list[i]
      return led_current(voltage(d[0]) - voltage(d[1])) if d[2] == name
      i += 1
    end
    list = @sources
    i = 0
    while i < list.size
      s = list[i]
      return (s[1] - voltage(s[0])) / s[2] if s[4] == name
      i += 1
    end
    nil
  end

  def led_current(v)
    LED_IS * (Math.exp(v / LED_NVT) - 1.0)
  end

  def solve
    nodes = collect_nodes
    n = nodes.size
    index = {}
    i = 0
    while i < n
      index[nodes[i]] = i
      i += 1
    end
    # Start every LED just below where it lights, the region it ends up in
    # whenever it does light.
    led_v = []
    i = 0
    while i < @leds.size
      led_v << LED_ON_V - 0.3
      i += 1
    end
    x = nil
    iteration = 0
    while iteration < MAX_ITERATIONS
      g, rhs = stamp(n, index, led_v)
      x = gauss(g, rhs, n)
      settled = true
      i = 0
      while i < @leds.size
        d = @leds[i]
        target = node_value(x, index, d[0]) - node_value(x, index, d[1])
        step = target - led_v[i]
        if step > LED_STEP_V
          step = LED_STEP_V
          settled = false
        elsif step < -LED_STEP_V
          step = -LED_STEP_V
          settled = false
        end
        settled = false if step.abs > TOLERANCE_V
        led_v[i] += step
        i += 1
      end
      iteration += 1
      break if settled
    end
    @volts = {}
    i = 0
    while i < n
      @volts[nodes[i]] = x[i]
      i += 1
    end
    @led_v = led_v
    @driven = find_driven(nodes)
    @warnings = check
    self
  end

  private

  def collect_nodes
    seen = {}
    nodes = []
    add = lambda do |node|
      next if node == :gnd || seen[node]
      seen[node] = true
      nodes << node
    end
    i = 0
    while i < @resistors.size
      add.call(@resistors[i][0])
      add.call(@resistors[i][1])
      i += 1
    end
    i = 0
    while i < @leds.size
      add.call(@leds[i][0])
      add.call(@leds[i][1])
      i += 1
    end
    i = 0
    while i < @sources.size
      add.call(@sources[i][0])
      i += 1
    end
    nodes
  end

  def node_value(x, index, node)
    return 0.0 if node == :gnd
    x[index[node]]
  end

  # Conductance matrix and injected currents, with each LED as the straight
  # line touching its curve at led_v.
  def stamp(n, index, led_v)
    g = []
    rhs = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < n
        row << 0.0
        j += 1
      end
      row[i] = GMIN
      g << row
      rhs << 0.0
      i += 1
    end
    i = 0
    while i < @resistors.size
      r = @resistors[i]
      stamp_conductance(g, index, r[0], r[1], 1.0 / r[2])
      i += 1
    end
    i = 0
    while i < @leds.size
      d = @leds[i]
      v = led_v[i]
      e = Math.exp(v / LED_NVT)
      gd = LED_IS * e / LED_NVT + GMIN
      # i(v) ~ i(v0) + gd * (v - v0): a conductance gd in parallel with a
      # constant current i(v0) - gd * v0 from anode to cathode.
      ieq = LED_IS * (e - 1.0) - gd * v
      stamp_conductance(g, index, d[0], d[1], gd)
      rhs[index[d[0]]] -= ieq unless d[0] == :gnd
      rhs[index[d[1]]] += ieq unless d[1] == :gnd
      i += 1
    end
    i = 0
    while i < @sources.size
      s = @sources[i]
      # A voltage behind a resistance is the same, seen from its point, as a
      # conductance to ground and a current volts / ohms pushed in.
      unless s[0] == :gnd
        k = index[s[0]]
        g[k][k] += 1.0 / s[2]
        rhs[k] += s[1] / s[2]
      end
      i += 1
    end
    [g, rhs]
  end

  def stamp_conductance(g, index, a, b, c)
    ia = a == :gnd ? nil : index[a]
    ib = b == :gnd ? nil : index[b]
    g[ia][ia] += c if ia
    g[ib][ib] += c if ib
    if ia && ib
      g[ia][ib] -= c
      g[ib][ia] -= c
    end
  end

  # Gaussian elimination with partial pivoting. The matrices are as small as
  # the circuit (a strip per point), so nothing cleverer is needed.
  def gauss(a, b, n)
    col = 0
    while col < n
      pivot = col
      best = a[col][col].abs
      r = col + 1
      while r < n
        v = a[r][col].abs
        if v > best
          best = v
          pivot = r
        end
        r += 1
      end
      if pivot != col
        a[col], a[pivot] = a[pivot], a[col]
        b[col], b[pivot] = b[pivot], b[col]
      end
      p = a[col][col]
      r = col + 1
      while r < n
        f = a[r][col] / p
        if f != 0.0
          row = a[r]
          top = a[col]
          c = col
          while c < n
            row[c] -= f * top[c]
            c += 1
          end
          b[r] -= f * b[col]
        end
        r += 1
      end
      col += 1
    end
    x = []
    i = 0
    while i < n
      x << 0.0
      i += 1
    end
    i = n - 1
    while i >= 0
      s = b[i]
      c = i + 1
      while c < n
        s -= a[i][c] * x[c]
        c += 1
      end
      x[i] = s / a[i][i]
      i -= 1
    end
    x
  end

  # Points joined to a source or to ground through resistors, switches, or
  # LEDs that are conducting. Behind an LED that is off, a point is as good
  # as unconnected.
  def find_driven(nodes)
    links = {}
    link = lambda do |a, b|
      (links[a] ||= []) << b
      (links[b] ||= []) << a
    end
    i = 0
    while i < @resistors.size
      link.call(@resistors[i][0], @resistors[i][1])
      i += 1
    end
    i = 0
    while i < @leds.size
      d = @leds[i]
      link.call(d[0], d[1]) if led_current(@led_v[i]) > 1.0e-6
      i += 1
    end
    driven = {}
    queue = [:gnd]
    i = 0
    while i < @sources.size
      queue << @sources[i][0]
      i += 1
    end
    while (node = queue.shift)
      next if driven[node]
      driven[node] = true
      nexts = links[node]
      queue.concat(nexts) if nexts
    end
    driven
  end

  def check
    out = []
    i = 0
    while i < @sources.size
      s = @sources[i]
      a = (s[1] - voltage(s[0])) / s[2]
      if a.abs > s[3]
        out << [:overcurrent, s[4], a]
      end
      i += 1
    end
    i = 0
    while i < @leds.size
      a = led_current(@led_v[i])
      out << [:led_overcurrent, @leds[i][2], a] if a > LED_MAX_A
      i += 1
    end
    out
  end
end
