# Browser glue for the simulator: renders the panel and runs the code typed into
# the page. Everything worth testing — the virtual chips, the coordinate
# composition and the LedMatrix facade — lives in sim_panel.rb and knows nothing
# about JavaScript, so this file is the only part that needs a browser.
require 'js'


$matrix = LedMatrix.new

# Available to the code typed into the page.
def matrix
  $matrix
end

module SimUI
  EXAMPLES = [
    ["1ドット", "one_dot.rb"],
    ["L 字（チップ境界をまたぐ）", "l_shape.rb"],
    ["初期化忘れ（光らない）", "forgot_setup.rb"],
    ["市松模様", "checker.rb"],
    ["枠と対角線", "frame.rb"]
  ]

  def self.render
    JS.global.renderPanel($matrix.panel.levels)
    nil
  end

  def self.status(text, kind)
    el = JS.document.getElementById('status')
    el[:className] = kind
    el[:textContent] = text
    nil
  end

  def self.run(code)
    eval(code)
    render
    status("OK", "ok")
  rescue => e
    render
    status("#{e.class}: #{e.message}", "error")
  end

  def self.load_example(path)
    JS.global.fetch("examples/#{path}")
      .then do |response|
        response.text.then do |text|
          JS.document.getElementById('code')[:value] = text
        end
      end
    nil
  end

  def self.setup
    select = JS.document.getElementById('examples')
    i = 0
    while i < EXAMPLES.size
      option = JS.document.createElement('option')
      option[:value] = EXAMPLES[i][1]
      option[:textContent] = EXAMPLES[i][0]
      select.appendChild(option)
      i += 1
    end

    select.addEventListener('change') do |event|
      load_example(event[:target][:value].to_s)
    end

    JS.document.getElementById('run').addEventListener('click') do |_event|
      run(JS.document.getElementById('code')[:value].to_s)
    end

    JS.document.getElementById('reset').addEventListener('click') do |_event|
      $matrix = LedMatrix.new(global_current: JS.document.getElementById('gcc')[:value].to_s.to_i)
      render
      status("リセットしました", "ok")
    end

    JS.document.getElementById('gcc').addEventListener('input') do |event|
      value = event[:target][:value].to_s.to_i
      JS.document.getElementById('gcc-value')[:textContent] = value.to_s
      $matrix.brightness = value
      render
    end

    JS.document.getElementById('run')[:disabled] = false
    JS.document.getElementById('reset')[:disabled] = false
    load_example(EXAMPLES[0][1])
    render
    status("準備できました。Run を押してください。", "ok")
    nil
  end
end

SimUI.setup
