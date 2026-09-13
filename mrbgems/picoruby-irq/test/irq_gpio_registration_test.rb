class IRQGPIORegistrationTest < Picotest::Test
  # Pins nothing else in the test build touches; see ports/posix/irq.c.
  def pin
    6
  end

  def other_pin
    7
  end

  def setup
    @seen = []
    @instances = []
    IRQ.simulate_gpio(pin, 1)
    IRQ.simulate_gpio(other_pin, 1)
    drain
  end

  def teardown
    @instances.each { |instance| instance.unregister }
    drain
  end

  def drain
    IRQ.process(100)
  end

  # FemtoRuby blocks cannot reach the locals of a method that has
  # returned, so the log and a tag travel as the capture.
  def listen(gpio_pin, tag)
    gpio = GPIO.new(gpio_pin, GPIO::IN)
    instance = gpio.irq(GPIO::EDGE_FALL, capture: [@seen, tag]) do |_peri, _event_type, cap|
      cap[0] << cap[1]
    end
    @instances << instance
    instance
  end

  def tap(gpio_pin)
    IRQ.simulate_gpio(gpio_pin, 0)
    IRQ.simulate_gpio(gpio_pin, 1)
    drain
  end

  def handler_count
    IRQ::HANDLER.size
  end

  def test_registering_a_pin_again_hands_it_to_the_newer_registration
    listen(pin, :old)
    listen(pin, :new)
    tap(pin)
    # The earlier registration used to take every event on the pin.
    assert_equal [:new], @seen
  end

  def test_running_the_same_registration_again_does_not_pile_up
    before = handler_count
    listen(pin, :first)
    listen(pin, :second)
    listen(pin, :third)
    assert_equal before + 1, handler_count
  end

  def test_a_replaced_registration_unregisters_to_false_and_leaves_the_new_one
    old = listen(pin, :old)
    listen(pin, :new)
    assert_false old.unregister
    tap(pin)
    assert_equal [:new], @seen
  end

  def test_a_replaced_id_reused_by_another_pin_is_not_touched
    old = listen(pin, :old)
    listen(pin, :new)            # frees old's slot
    listen(other_pin, :other)    # may be given that slot's id
    assert_false old.unregister
    tap(other_pin)
    assert_equal [:other], @seen
  end

  def test_other_pins_are_left_alone
    listen(pin, :a)
    listen(other_pin, :b)
    tap(pin)
    tap(other_pin)
    assert_equal [:a, :b], @seen
  end

  def test_unregistering_twice_is_false_the_second_time
    instance = listen(pin, :x)
    assert_true instance.unregister
    assert_false instance.unregister
  end
end
