MRuby::Gem::Specification.new('picoruby-is31fl3729') do |spec|
  spec.license = 'MIT'
  spec.author  = 'kishima'
  spec.summary = 'IS31FL3729 matrix LED driver (up to 16x8, 8-bit PWM per dot) over I2C'

  # picoruby-i2c is deliberately NOT declared as a dependency, even though
  # mrblib/is31fl3729.rb requires it. It has no posix port, so pulling it into
  # the host test runner leaves I2C_write_timeout_us and friends undefined at
  # link time. picoruby-adc does the same with picoruby-gpio for this reason.
  #
  # Every target that uses this gem gets I2C from the `peripherals` gembox, and
  # `require 'i2c'` resolves against the built-in gem at run time. The tests
  # stand in for it with test/mock/i2c.rb.
end
