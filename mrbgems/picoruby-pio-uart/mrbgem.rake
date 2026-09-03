MRuby::Gem::Specification.new('picoruby-pio-uart') do |spec|
  spec.license = 'MIT'
  spec.author  = 'picorubykaigi01-board'
  spec.summary = 'PIO + DMA engine behind UART\'s PIO_UART0 unit'

  # No Ruby side and no gem dependencies: this is the engine that
  # picoruby-uart's RP2 port calls when it is asked for the PIO unit.
  # Everything a program sees is UART.
end
