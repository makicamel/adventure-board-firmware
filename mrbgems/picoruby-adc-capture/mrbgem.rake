MRuby::Gem::Specification.new('picoruby-adc-capture') do |spec|
  spec.license = 'MIT'
  spec.author  = 'picorubykaigi01-board'
  spec.summary = 'Free-running ADC capture into a RAM ring, read back over SWD'

  # A bench tool, not something a sample calls: it records one ADC pin with
  # DMA, without the CPU, until told to stop, so that a glitch that shows up
  # once a minute is still in memory when someone says "there it was".
end
