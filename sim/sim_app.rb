# The simulator's UI, as a Funicular component.
#
# Funicular is PicoRuby.wasm's VDOM framework and ships in the stock package, so
# the whole page is Ruby. Three things stay outside it and are reached through
# refs: the canvas, the code box and the note log. That is the framework's own
# pattern (demo/www/webaudio.rb draws its scope the same way) and it is there
# for a reason — all three change far too often to be worth a VDOM diff, and a
# textarea whose value lives in state loses the caret on every keystroke.
#
# Careful with method names: every HTML tag is a reserved word on a Component,
# so `code`, `audio`, `select` and friends cannot be used here.
require 'js'
require 'syntax-highlight'   # only in the wasm from `rake sim:wasm`; the stock one goes without colours

# Bringing the board up is the one thing that genuinely differs between here
# and the device, so it is the one thing done here: the peripherals are
# stand-ins and the audio sink can be switched on later. Everything a program
# touches — `board`, `matrix`, `buttons`, `speaker` — comes from the board
# layer and is identical on the device.
$panel = Panel.new
$notelog = NoteLog.new
$audio_sink = SwitchableSink.new
$board = Board.boot(i2c: $panel.i2c, speaker_backend: $audio_sink)
$board.speaker.router.connect(:mml, $notelog)
$app = nil
# The real board over USB. Page machinery like the note log: a sample never
# sees it, it only carries the sample to the board.
$device = DeviceLink.new


# Turns a program into HTML for the coloured copy of the code box: one
# <span class="kN"> per run of bytes that SyntaxHighlight gave the same
# category. Prism's tokens begin and end on character boundaries, so cutting
# the source at those bytes never splits a character.
module CodeColors
  def self.html(source)
    kinds = SyntaxHighlight.tokenize(source)
    return escape(source) if kinds.nil? || kinds.bytesize != source.bytesize
    out = ""
    size = source.bytesize
    start = 0
    while start < size
      kind = kinds.getbyte(start)
      stop = start + 1
      while stop < size && kinds.getbyte(stop) == kind
        stop += 1
      end
      text = escape(source.byteslice(start, stop - start).to_s)
      if kind == 0
        out << text
      else
        out << "<span class=\"k#{kind}\">" << text << "</span>"
      end
      start = stop
    end
    # A <pre> gives no height to a line break at its very end; the textarea
    # does, and the two have to stay the same height to scroll together.
    out << " " if source.end_with?("\n")
    out
  end

  def self.escape(text)
    text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  end
end

class SimApp < Funicular::Component
  EXAMPLES = [
    ["漢字（要ローカル wasm）", "kanji.rb"],
    ["文字スクロール（要ローカル wasm）", "scroll.rb"],
    ["線と矩形（要ローカル wasm）", "shapes.rb"],
    ["1ドット", "one_dot.rb"],
    ["ステータス LED", "status_led.rb"],
    ["ボタンで動かす", "buttons.rb"],
    ["自動で動く（ループ確認）", "spinner.rb"],
    ["MML でメロディ", "melody.rb"],
    ["音に合わせて光る", "sound_and_light.rb"],
    ["L 字（チップ境界をまたぐ）", "l_shape.rb"],
    ["左端の縦一列（列反転の確認）", "left_column.rb"],
    ["初期化忘れ（光らない）", "forgot_setup.rb"],
    ["市松模様", "checker.rb"],
    ["枠と対角線", "frame.rb"],
    ["グラデーション", "gradient.rb"]
  ]

  # Pins as on the board (Board::BUTTON_PINS). B sits left of A there too.
  BUTTON_PINS = [
    [17, "↑", "up"], [18, "←", "left"], [19, "→", "right"], [20, "↓", "down"]
  ]
  AB_PINS = [[21, "B"], [22, "A"]]

  KEY_PINS = {
    "ArrowUp" => 17, "ArrowLeft" => 18, "ArrowRight" => 19, "ArrowDown" => 20,
    "z" => 22, "Z" => 22, "x" => 21, "X" => 21
  }

  MONITOR_MS = 50

  # --- the run loop, which outlives any one render -------------------------

  # The code typed into the page runs in a task of its own, so it can be
  # written exactly as it would be on the board — `while true` with `sleep_ms`,
  # which suspends the task and hands the browser back its event loop. Nothing
  # here is a simulator-only construct; a sample that runs on this page runs on
  # the device unchanged.
  def self.stop_task
    task = $user_task
    $user_task = nil
    return nil unless task
    begin
      task.terminate
    rescue Exception
      nil # already finished
    end
    nil
  end

  def self.start_task(source)
    stop_task
    $user_task = Task.new(name: "sim-user") do
      begin
        eval(source)
      rescue Exception => e
        $app.report("実行エラー", e) if $app
      end
    end
    nil
  end

  # --- state ---------------------------------------------------------------

  def initialize_state
    {
      status: "準備しています…",
      kind: "busy",
      gcc: 32,
      audio_on: false,
      notes_visible: false,
      held: [],
      device: :none,
      device_supported: DeviceLink.supported?
    }
  end

  def component_mounted
    $app = self
    wire_keyboard
    start_monitor
    draw
    patch(status: "準備できました。Run を押してください。", kind: "ok")
    load_example(EXAMPLES[0][1])
    nil
  end

  # A re-render can hand back a fresh canvas, which would be blank.
  def component_updated
    draw
    nil
  end

  # --- render --------------------------------------------------------------

  def render
    div(class: "wrap") do
      div(class: "panel-side") do
        canvas(ref: :panel, id: "panel", width: "452", height: "452")
        div(class: "controls") do
          label(for: "gcc") { "明るさ (GCC)" }
          input(type: "range", id: "gcc", min: "0", max: "64",
                value: state[:gcc].to_s, oninput: :on_gcc)
          span { state[:gcc].to_s }
        end
        div(class: "pad") do
          div(class: "dpad") { dpad_buttons }
          div(class: "ab") { ab_buttons }
        end
        div(class: "leds") do
          # The green status LED and, beside it, the red power one that is
          # wired straight to 3V3 on the board and so is always lit.
          span(ref: :status_led, id: "status-led", class: "led green off") { "" }
          span(class: "led red") { "" }
          span(class: "legend") { "ステータス LED (GPIO16) / 電源 LED" }
        end
        div(class: "legend") do
          span { "上半分 = U10 (0x34) / 下半分 = U11 (0x35、列が左右反転)" }
          br
          span { "ボタンはキーボードでも操作できます（矢印キー / Z=A / X=B）" }
        end
      end

      div(class: "code-side") do
        div(class: "controls") do
          select(id: "examples", onchange: :on_example) { example_options }
          button(id: "run", class: "primary", onclick: :on_run) { "Run" }
          button(id: "audio", onclick: :on_audio) { state[:audio_on] ? "音: 有効" : "音を有効にする" }
          button(id: "notes-toggle", onclick: :on_notes_toggle) do
            state[:notes_visible] ? "鳴った音を隠す" : "鳴った音を見る"
          end
          button(id: "reset", onclick: :on_reset) { "Reset" }
        end
        div(class: "controls") { device_controls }
        div(class: "editor") do
          tag("pre", id: "code-colors") { "" }
          textarea(ref: :codebox, id: "code", spellcheck: "false")
        end
        div(id: "status", class: state[:kind]) { state[:status] }
        div(class: "legend", style: "margin-top:12px",
            hidden: state[:device] == :none ? "hidden" : nil) do
          "実機の出力"
        end
        tag("pre", ref: :devicelog, id: "devicelog",
            hidden: state[:device] == :none ? "hidden" : nil)
        # Kept in the document even when hidden: it is how a melody can be
        # checked without hearing it, and the browser harness reads it.
        div(class: "legend", style: "margin-top:12px",
            hidden: state[:notes_visible] ? nil : "hidden") do
          "鳴った音"
        end
        # `pre` is not one of the DSL's tags, so it goes through the generic
        # helper.
        tag("pre", ref: :notes, id: "notelog",
            hidden: state[:notes_visible] ? nil : "hidden")
      end
    end
  end

  private

  # These add their elements to whatever block is being captured, so nothing
  # needs to be collected or returned.
  def device_controls
    unless state[:device_supported]
      span(class: "legend") { "実機への接続は Chrome / Edge でだけ使えます" }
      return nil
    end
    connected = state[:device] != :none
    busy = state[:device] == :busy
    button(id: "device-connect", onclick: :on_device_connect,
           disabled: busy ? "disabled" : nil) do
      connected ? "実機を切断" : "実機に接続"
    end
    button(id: "device-run", class: "primary", onclick: :on_device_run,
           disabled: (connected && !busy) ? nil : "disabled") do
      "実機で実行"
    end
    span(class: "legend") { "USB でつなぐ。ポートは R2P2 の 1 番目（CDC0）を選ぶ" }
    nil
  end

  def example_options
    list = EXAMPLES
    i = 0
    while i < list.size
      option(value: list[i][1]) { list[i][0] }
      i += 1
    end
    nil
  end

  def dpad_buttons
    list = BUTTON_PINS
    i = 0
    while i < list.size
      pad_button(list[i][0], list[i][1], "grid-area:#{list[i][2]}", "btn")
      i += 1
    end
    nil
  end

  def ab_buttons
    list = AB_PINS
    i = 0
    while i < list.size
      pad_button(list[i][0], list[i][1], nil, "btn round")
      i += 1
    end
    nil
  end

  # The handlers are symbols, not blocks, so nothing closes over `pin` — which
  # is what went wrong the last time these were built in a loop.
  def pad_button(pin, glyph, style, base)
    klass = state[:held].include?(pin) ? "#{base} held" : base
    button(class: klass, style: style, "data-pin": pin.to_s,
           onmousedown: :on_press, onmouseup: :on_release,
           onmouseleave: :on_release, ontouchstart: :on_press,
           ontouchend: :on_release) { glyph }
  end

  # --- handlers ------------------------------------------------------------

  def pin_of(event)
    target = event.target
    return nil unless target
    value = target.getAttribute('data-pin')
    return nil if value.nil?
    value.to_s.to_i
  end

  def on_press(event)
    pin = pin_of(event)
    hold(pin, true) if pin
    nil
  end

  def on_release(event)
    pin = pin_of(event)
    hold(pin, false) if pin
    nil
  end

  def hold(pin, down)
    if down
      GPIO.press(pin)
      held = state[:held]
      patch(held: held + [pin]) unless held.include?(pin)
    else
      GPIO.release(pin)
      held = state[:held]
      patch(held: held - [pin]) if held.include?(pin)
    end
    nil
  end

  def on_gcc(event)
    value = event.target[:value].to_s.to_i
    patch(gcc: value)
    matrix.brightness = value
    draw
    nil
  end

  def on_example(event)
    load_example(event.target[:value].to_s)
    nil
  end

  def on_run(_event)
    box = refs[:codebox]
    run(box ? box[:value].to_s : "")
    nil
  end

  def on_reset(_event)
    begin
      SimApp.stop_task
      speaker.stop if speaker
      $notelog.clear
      GPIO.reset
      $panel = Panel.new
      $board = Board.boot(i2c: $panel.i2c, speaker_backend: $audio_sink,
                          global_current: state[:gcc])
      $board.speaker.router.connect(:mml, $notelog)
      patch(held: [], status: "リセットしました", kind: "ok")
      draw
    rescue Exception => e
      report("リセット", e)
    end
    nil
  end

  # Runs on the click itself: the browser only shows its port picker for a
  # user gesture.
  def on_device_connect(_event)
    begin
      if $device.connected?
        $device.disconnect
        patch(device: :none, status: "実機を切断しました", kind: "ok")
      else
        $device.connect
        patch(device: :connected, kind: "ok",
              status: "実機に接続しました。シェルの出力は下に出ます。")
      end
    rescue Exception => e
      patch(device: $device.connected? ? :connected : :none)
      report("実機への接続", e)
    end
    nil
  end

  # The transfer waits on the board many times over, so it runs in a task of
  # its own and reports back when it is done.
  def on_device_run(_event)
    box = refs[:codebox]
    source = box ? box[:value].to_s : ""
    patch(device: :busy, status: "実機に送っています…", kind: "busy")
    Task.new(name: "device-run") do
      begin
        $device.run(source)
        $app.device_finished(nil) if $app
      rescue Exception => e
        $app.device_finished(e) if $app
      end
    end
    nil
  end

  def device_finished(error)
    state_now = $device.connected? ? :connected : :none
    if error
      patch(device: state_now)
      report("実機で実行", error)
    else
      patch(device: state_now, kind: "ok",
            status: "実機で実行しています（#{DeviceLink::PATH}）。止めるには、もう一度実行するか切断してください。")
    end
    nil
  end

  # Synchronous on purpose: the browser only lifts its autoplay block for code
  # running on the gesture's own stack.
  def on_notes_toggle(_event)
    patch(notes_visible: !state[:notes_visible])
    nil
  end

  def on_audio(_event)
    begin
      unless $audio_sink.backend
        web = WebAudioSpeaker.new
        web.resume
        $audio_sink.backend = web
      end
      patch(audio_on: true, status: "音を有効にしました。", kind: "ok")
    rescue Exception => e
      report("音の有効化", e)
    end
    nil
  end

  # --- work ----------------------------------------------------------------

  def run(source)
    begin
      SimApp.stop_task
      speaker.stop if speaker
      $notelog.clear
      SimApp.start_task(source)
      patch(status: "実行中", kind: "ok")
    rescue Exception => e
      # Exception, not StandardError: a syntax error in the typed code is a
      # ScriptError and would otherwise kill the task without a word.
      report("実行エラー", e)
    end
    nil
  end

  def report(prefix, e)
    message = "#{prefix}: #{e.class}: #{e.message}"
    patch(status: message, kind: "error")
    JS.global[:console].error(message)
    nil
  end

  def draw
    JS.global.renderPanel($panel.levels_hex)
    draw_status_led
    draw_notes
    draw_device
    draw_code_colors
    nil
  end

  # The code box in colour. Read on the heartbeat like everything else, and
  # only worked out again when the text is not what was coloured last: that
  # covers typing, a pasted program and a loaded example alike, with nobody
  # having to say so. SyntaxHighlight comes with `rake sim:wasm`; the stock
  # package does not have it, and then the box stays as plain as it was.
  def draw_code_colors
    return if @code_colors_missing
    box = refs[:codebox]
    return unless box
    source = box[:value].to_s
    return if source == @colored_source
    @colored_source = source
    JS.global.setCodeColors(CodeColors.html(source))
    nil
  rescue Exception => e
    # Once, not twenty times a second. A wasm without SyntaxHighlight lands
    # here with a NameError, and that one is expected and not worth a line.
    @code_colors_missing = true
    puts "code colours are off: #{e.class}: #{e.message}" unless e.is_a?(NameError)
    nil
  end

  # The log is read on the heartbeat, like the notes. So is a cable pulled out:
  # the port goes away without anyone clicking anything.
  def draw_device
    if state[:device] != :none && !$device.connected?
      patch(device: :none, status: "実機との接続が切れました", kind: "error")
    end
    el = refs[:devicelog]
    return nil unless el
    text = $device.log
    return nil if text == $device_log_shown
    $device_log_shown = text
    el[:textContent] = text
    el[:scrollTop] = el[:scrollHeight].to_i
    nil
  end

  # Read on the heartbeat like the panel: the board layer drives the pin and
  # the page shows whatever it currently is.
  def draw_status_led
    el = refs[:status_led]
    return nil unless el
    led = $board.status_led
    lit = led && led.on?
    return nil if lit == $status_led_shown
    $status_led_shown = lit
    el[:className] = lit ? "led green" : "led green off"
    nil
  end

  def draw_notes
    el = refs[:notes]
    return nil unless el
    text = $notelog.to_s
    return nil if text == $notes_shown
    $notes_shown = text
    el[:textContent] = text
    el[:scrollTop] = el[:scrollHeight].to_i
    nil
  end

  # The panel is redrawn on a heartbeat rather than by whoever changed it,
  # which is what a real one does: the driver scans it continuously and the
  # display shows whatever the chips currently hold. It means the code typed
  # into the page never has to tell the simulator to repaint, and a melody
  # playing in its own task still gets its notes shown.
  def start_monitor
    JS.global.setTimeout(MONITOR_MS) do
      begin
        draw
      rescue Exception
        nil
      end
      start_monitor
    end
    nil
  end

  def wire_keyboard
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

  def load_example(path)
    # no-store: a hard reload only bypasses the cache for the document and what
    # it loads directly. A fetch the page makes afterwards still goes through
    # the HTTP cache, so an edited example would keep coming back stale however
    # many times the page was reloaded.
    JS.global.fetch("examples/#{path}", { cache: "no-store" }) do |response|
      begin
        if response[:ok]
          box = refs[:codebox]
          box[:value] = response.text.await if box
        else
          report("サンプルの取得", RuntimeError.new("#{path}: #{response[:status].to_i}"))
        end
      rescue Exception => e
        report("サンプルの取得", e)
      end
    end
    nil
  end

  # The run loop is a class method — it outlives any one render — and it pokes
  # the mounted instance, so these two cannot stay private.
  public :draw, :report, :device_finished
end

Funicular.start(SimApp, container: 'app')
