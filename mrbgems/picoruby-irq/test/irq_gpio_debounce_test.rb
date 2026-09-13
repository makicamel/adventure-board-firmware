class IRQGPIODebounceTest < Picotest::Test
  # A pin nothing else in the test build touches. The host port keeps a
  # simulated level per pin and a millisecond clock; see ports/posix/irq.c.
  def pin
    5
  end

  def setup
    @gpio = GPIO.new(pin, GPIO::IN)
    @seen = []
    @instance = nil
    settle_high
  end

  def teardown
    @instance.unregister if @instance
    settle_high
  end

  def settle_high
    IRQ.simulate_gpio(pin, 1)
    IRQ.simulate_elapse(1000)
    drain
    @seen = []
  end

  # The log goes in as the capture: FemtoRuby blocks cannot reach the
  # locals of a method that has returned.
  def listen(mask, debounce)
    @instance = @gpio.irq(mask, debounce: debounce, capture: @seen) do |_peri, event_type, seen|
      seen << event_type
    end
  end

  def drain
    IRQ.process(100)
  end

  def set(level, then_ms)
    IRQ.simulate_gpio(pin, level)
    IRQ.simulate_elapse(then_ms)
  end

  # A tact switch as it was measured on a board: it chatters on the way
  # down and again on the way up, one millisecond apart.
  def press(hold: 100, gap: 100)
    set(0, 1); set(1, 1); set(0, hold)
    set(1, 1); set(0, 1); set(1, gap)
  end

  def falls(n)
    Array.new(n, GPIO::EDGE_FALL)
  end

  def fall_rise(n)
    out = []
    n.times { out << GPIO::EDGE_FALL << GPIO::EDGE_RISE }
    out
  end

  def test_a_bouncy_press_is_one_fall_even_when_only_falls_are_asked_for
    listen(GPIO::EDGE_FALL, 20)
    3.times { press }
    drain
    # The old rule compared a fall only with the previous fall, so the
    # chatter of each release came through as another press: 6.
    assert_equal falls(3), @seen
  end

  def test_both_edges_report_each_change_once
    listen(GPIO::EDGE_FALL | GPIO::EDGE_RISE, 20)
    3.times { press }
    drain
    # The old rule dropped nothing here: fall and rise alternate, so no
    # event was ever the same kind as the one before it.
    assert_equal fall_rise(3), @seen
  end

  def test_the_first_edge_is_reported_without_waiting_for_the_window
    listen(GPIO::EDGE_FALL, 20)
    set(0, 0)
    drain
    assert_equal falls(1), @seen
  end

  def test_a_tap_shorter_than_the_window_is_not_lost
    listen(GPIO::EDGE_FALL | GPIO::EDGE_RISE, 20)
    set(0, 5)
    set(1, 50)
    drain
    # The rise fell inside the window; the sample that closes it finds
    # the pin back up and reports that.
    assert_equal fall_rise(1), @seen
  end

  def test_a_release_inside_the_window_still_lets_the_next_press_through
    listen(GPIO::EDGE_FALL, 20)
    set(0, 5)
    set(1, 50)   # released during the window, reported (and filtered) late
    set(0, 50)
    drain
    assert_equal falls(2), @seen
  end

  def test_presses_further_apart_than_the_window_are_all_reported
    listen(GPIO::EDGE_FALL, 20)
    5.times { press(hold: 25, gap: 25) }
    drain
    assert_equal falls(5), @seen
  end

  def test_without_debounce_every_edge_is_reported
    listen(GPIO::EDGE_FALL, 0)
    press
    drain
    assert_equal falls(3), @seen
  end

  def test_an_open_window_does_not_outlive_its_registration
    listen(GPIO::EDGE_FALL | GPIO::EDGE_RISE, 20)
    set(0, 5)
    drain
    @instance.unregister
    @instance = nil
    set(1, 50)   # the window would close here and report this rise
    assert_equal 0, drain
    assert_equal [GPIO::EDGE_FALL], @seen
  end
end
