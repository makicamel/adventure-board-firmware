MRuby::Gem::Specification.new('picoruby-pio-uart') do |spec|
  spec.license = 'MIT'
  spec.author  = 'picorubykaigi01-board'
  spec.summary = 'A UART on PIO, received into a DMA ring buffer'

  # GPIO for the receive pin's pull-up. picoruby-pio is deliberately not a
  # dependency: this gem drives the state machines itself, because the buffer
  # has to be filled by DMA rather than by anything Ruby does.
  spec.add_dependency 'picoruby-gpio'
end
