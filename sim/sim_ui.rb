# Browser glue for the simulator: renders the panel and runs the code typed into
# the page. Everything worth testing — the virtual chips, the coordinate
# composition and the LedMatrix facade — lives in sim_panel.rb and knows nothing
# about JavaScript, so this file is the only part that needs a browser.
require 'js'

# The page boots the real board layer against the simulated peripherals, so the
# code typed into it is the code that would run on the board.
$panel = Panel.new
$board = Board.boot(i2c: $panel.i2c)
$matrix = $board.matrix

# Available to the code typed into the page.
def matrix
  $matrix
end

def buttons
  $board.buttons
end

def board
  $board
end

# The simulated panel behind the matrix: virtual chips and the virtual bus.
def panel
  $panel
end

# Repeat a block until the next Run. Games and animations need time to pass,
# and a Ruby task cannot simply loop: it has to hand control back to the
# browser. The buttons are sampled before each call, which is what a main loop
# on the board would do anyway.
def every(ms, &block)
  SimUI.start_loop(ms, &block)
end

module SimUI
  EXAMPLES = [
    ["1ドット", "one_dot.rb"],
    ["ボタンで動かす", "buttons.rb"],
    ["自動で動く（ループ確認）", "spinner.rb"],
    ["L 字（チップ境界をまたぐ）", "l_shape.rb"],
    ["左端の縦一列（列反転の確認）", "left_column.rb"],
    ["初期化忘れ（光らない）", "forgot_setup.rb"],
    ["市松模様", "checker.rb"],
    ["枠と対角線", "frame.rb"],
    ["グラデーション", "gradient.rb"]
  ]

  def self.render
    JS.global.renderPanel($panel.levels_hex)
    nil
  end

  def self.status(text, kind)
    el = JS.document.getElementById('status')
    el[:className] = kind
    el[:textContent] = text
    nil
  end

  # Anything that goes wrong has to be visible: a task that dies quietly looks
  # exactly like a simulator that works but draws nothing.
  def self.report(prefix, e)
    message = "#{prefix}: #{e.class}: #{e.message}"
    status(message, "error")
    JS.global[:console].error(message)
    nil
  end

  # Scheduled with setTimeout rather than a Ruby loop, and re-armed after each
  # call instead of with setInterval, so a slow block cannot pile up.
  def self.stop_loop
    id = $loop_id
    JS.global.clearTimeout(id) if id
    $loop_id = nil
    $loop_block = nil
    nil
  end

  def self.start_loop(ms, &block)
    stop_loop
    $loop_block = block
    $loop_ms = ms
    schedule
    nil
  end

  def self.schedule
    ms = $loop_ms
    $loop_id = JS.global.setTimeout(ms) do
      block = $loop_block
      if block
        begin
          $board.buttons.update
          block.call
          render
          schedule if $loop_block
        rescue Exception => e
          stop_loop
          report("ループ", e)
        end
      end
    end
    nil
  end

  def self.run(code)
    begin
      stop_loop
      eval(code)
      render
      status("OK", "ok")
    rescue Exception => e
      # Exception, not StandardError: a syntax error in the typed code is a
      # ScriptError and would otherwise kill the task without a word.
      render
      report("実行エラー", e)
    end
    nil
  end

  # Four corners plus a centre cross, driven through the real driver. If this
  # shows up, both the rendering and the whole driver path are working, which
  # separates "nothing is drawn" from "nothing was lit".
  def self.self_test
    m = $matrix
    m.clear
    m.set(1, 1)
    m.set(16, 1)
    m.set(1, 16)
    m.set(16, 16)
    i = 6
    while i <= 11
      m.set(i, 8)
      m.set(8, i)
      i += 1
    end
    m.show
    render
    nil
  end

  def self.load_example(path)
    JS.global.fetch("examples/#{path}") do |response|
      begin
        if response[:ok]
          JS.document.getElementById('code')[:value] = response.text.await
        else
          report("サンプルの取得", RuntimeError.new("#{path}: #{response[:status].to_i}"))
        end
      rescue Exception => e
        report("サンプルの取得", e)
      end
    end
    nil
  end

  def self.build_example_list
    select = JS.document.getElementById('examples')
    i = 0
    while i < EXAMPLES.size
      option = JS.document.createElement('option')
      option[:value] = EXAMPLES[i][1]
      option[:textContent] = EXAMPLES[i][0]
      select.appendChild(option)
      i += 1
    end
    select
  end

  # Held while the pointer or the key is down, because the board's buttons are
  # momentary and a game wants to know that, not just that a click happened.
  KEY_PINS = {
    "ArrowUp" => 17, "ArrowDown" => 18, "ArrowLeft" => 19, "ArrowRight" => 20,
    "z" => 21, "Z" => 21, "x" => 22, "X" => 22
  }

  def self.hold(pin, down)
    if down
      GPIO.press(pin)
    else
      GPIO.release(pin)
    end
    node = JS.document.querySelector("[data-pin=\"#{pin}\"]")
    node[:className] = down ? "btn held" : "btn" if node
    nil
  end

  # A method rather than the body of the loop below: `while` does not open a
  # scope, so blocks created inside one all close over the same `pin` variable
  # and every button would end up sending the last pin. A method argument is
  # fresh per call.
  def self.bind_button(node, pin)
    node.addEventListener('mousedown')  { |_e| hold(pin, true) }
    node.addEventListener('mouseup')    { |_e| hold(pin, false) }
    node.addEventListener('mouseleave') { |_e| hold(pin, false) }
    node.addEventListener('touchstart') { |_e| hold(pin, true) }
    node.addEventListener('touchend')   { |_e| hold(pin, false) }
    nil
  end

  def self.wire_buttons
    nodes = JS.document.querySelectorAll('.btn').to_a
    i = 0
    while i < nodes.size
      node = nodes[i]
      bind_button(node, node.getAttribute('data-pin').to_s.to_i)
      i += 1
    end

    JS.document.addEventListener('keydown') do |event|
      pin = KEY_PINS[event[:key].to_s]
      hold(pin, true) if pin
    end
    JS.document.addEventListener('keyup') do |event|
      pin = KEY_PINS[event[:key].to_s]
      hold(pin, false) if pin
    end
    nil
  end

  def self.wire(select)
    select.addEventListener('change') do |event|
      load_example(event.target[:value].to_s)
    end

    JS.document.getElementById('run').addEventListener('click') do |_event|
      run(JS.document.getElementById('code')[:value].to_s)
    end

    JS.document.getElementById('selftest').addEventListener('click') do |_event|
      begin
        self_test
        status("描画テスト: 四隅と中央の十字が光っていれば描画とドライバは正常です。", "ok")
      rescue Exception => e
        report("描画テスト", e)
      end
    end

    JS.document.getElementById('reset').addEventListener('click') do |_event|
      begin
        stop_loop
        GPIO.reset
        $panel = Panel.new
        $board = Board.boot(i2c: $panel.i2c,
                            global_current: JS.document.getElementById('gcc')[:value].to_s.to_i)
        $matrix = $board.matrix
        render
        status("リセットしました", "ok")
      rescue Exception => e
        report("リセット", e)
      end
    end

    JS.document.getElementById('gcc').addEventListener('input') do |event|
      begin
        value = event.target[:value].to_s.to_i
        JS.document.getElementById('gcc-value')[:textContent] = value.to_s
        $matrix.brightness = value
        render
      rescue Exception => e
        report("明るさ変更", e)
      end
    end
    nil
  end

  def self.setup
    select = build_example_list
    wire(select)
    wire_buttons

    JS.document.getElementById('run')[:disabled] = false
    JS.document.getElementById('reset')[:disabled] = false
    JS.document.getElementById('selftest')[:disabled] = false

    # Draw something before anything can go wrong, so a blank panel from here on
    # means no light rather than no rendering.
    self_test
    status("描画テスト中: 四隅と中央の十字が光っていれば準備完了です。Run で上書きされます。", "ok")

    # Last, and non-fatal: fetching an example must not take the page down.
    load_example(EXAMPLES[0][1])
    nil
  end
end

begin
  SimUI.setup
rescue Exception => e
  begin
    SimUI.report("起動", e)
  rescue Exception
    JS.global[:console].error("SimUI.setup failed: #{e.class}: #{e.message}")
  end
end
