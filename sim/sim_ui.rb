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
    ["左端の縦一列（列反転の確認）", "left_column.rb"],
    ["初期化忘れ（光らない）", "forgot_setup.rb"],
    ["市松模様", "checker.rb"],
    ["枠と対角線", "frame.rb"],
    ["グラデーション", "gradient.rb"]
  ]

  def self.render
    JS.global.renderPanel($matrix.panel.levels_hex)
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

  def self.run(code)
    begin
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
        $matrix = LedMatrix.new(global_current: JS.document.getElementById('gcc')[:value].to_s.to_i)
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
