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

$panel = Panel.new
$notelog = NoteLog.new
# Built on the first user gesture: creating an AudioContext before one makes the
# browser complain, and not every session wants sound.
$speaker_backend = nil
$board = Board.boot(i2c: $panel.i2c)
$matrix = $board.matrix
$app = nil

# --- what the code typed into the page can call -----------------------------

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

def speaker
  SimApp.speaker
end

# Repeat a block until the next Run. A Ruby task cannot simply loop in a
# browser; it has to hand control back. The buttons are sampled before each
# call, which is what a main loop on the board would do anyway.
def every(ms, &block)
  SimApp.start_loop(ms, &block)
end

class SimApp < Funicular::Component
  EXAMPLES = [
    ["漢字（要ローカル wasm）", "kanji.rb"],
    ["文字スクロール（要ローカル wasm）", "scroll.rb"],
    ["線と矩形（要ローカル wasm）", "shapes.rb"],
    ["1ドット", "one_dot.rb"],
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

  BUTTON_PINS = [
    [17, "↑", "up"], [19, "←", "left"], [20, "→", "right"], [18, "↓", "down"]
  ]
  AB_PINS = [[21, "A"], [22, "B"]]

  KEY_PINS = {
    "ArrowUp" => 17, "ArrowDown" => 18, "ArrowLeft" => 19, "ArrowRight" => 20,
    "z" => 21, "Z" => 21, "x" => 22, "X" => 22
  }

  MONITOR_MS = 150

  # --- the speaker and the run loop, which outlive any one render -----------

  def self.speaker
    return $speaker if $speaker
    $speaker = Speaker.new(sink: audio_sink, amp_sd_pin: Board::AMP_SD_PIN)
    $speaker.router.connect(:mml, $notelog)
    $speaker
  end

  # WebAudio once it has been switched on, otherwise a sink that swallows
  # events so a melody still reaches the note log.
  def self.audio_sink
    $speaker_backend || NullSink.new
  end

  class NullSink
    def handle(_event, source: :mml, priority: 0, timestamp_us: nil, **_c); true; end
    def handle_midi(_event, _source, _priority, _timestamp_us); true; end
  end

  # Re-armed after each call rather than setInterval, so a slow block cannot
  # pile up.
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
    $loop_id = JS.global.setTimeout($loop_ms) do
      block = $loop_block
      if block
        begin
          block.call
          $app.draw if $app
          schedule if $loop_block
        rescue Exception => e
          stop_loop
          $app.report("ループ", e) if $app
        end
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
      held: []
    }
  end

  def component_mounted
    $app = self
    wire_keyboard
    start_monitor
    self_test
    patch(status: "描画テスト中: 四隅と中央の十字が光っていれば準備完了です。Run で上書きされます。",
          kind: "ok")
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
          button(id: "selftest", onclick: :on_selftest) { "描画テスト" }
          button(id: "reset", onclick: :on_reset) { "Reset" }
        end
        textarea(ref: :codebox, id: "code", spellcheck: "false")
        div(id: "status", class: state[:kind]) { state[:status] }
        div(class: "legend", style: "margin-top:12px") do
          "鳴った音（音は聞こえなくてもここで確認できます）"
        end
        # `pre` is not one of the DSL's tags, so it goes through the generic
        # helper.
        tag("pre", ref: :notes, id: "notelog")
      end
    end
  end

  private

  # These add their elements to whatever block is being captured, so nothing
  # needs to be collected or returned.
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
    $matrix.brightness = value
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

  def on_selftest(_event)
    begin
      self_test
      patch(status: "描画テスト: 四隅と中央の十字が光っていれば描画とドライバは正常です。", kind: "ok")
    rescue Exception => e
      report("描画テスト", e)
    end
    nil
  end

  def on_reset(_event)
    begin
      SimApp.stop_loop
      $speaker.stop if $speaker
      $notelog.clear
      GPIO.reset
      $panel = Panel.new
      $board = Board.boot(i2c: $panel.i2c, global_current: state[:gcc])
      $matrix = $board.matrix
      patch(held: [], status: "リセットしました", kind: "ok")
      draw
    rescue Exception => e
      report("リセット", e)
    end
    nil
  end

  # Synchronous on purpose: the browser only lifts its autoplay block for code
  # running on the gesture's own stack.
  def on_audio(_event)
    begin
      unless $speaker_backend
        $speaker_backend = WebAudioSpeaker.new
        $speaker_backend.resume
        if $speaker
          $speaker.stop
          $speaker = nil
        end
        SimApp.speaker
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
      SimApp.stop_loop
      $speaker.stop if $speaker
      $notelog.clear
      eval(source)
      draw
      patch(status: "OK", kind: "ok")
    rescue Exception => e
      # Exception, not StandardError: a syntax error in the typed code is a
      # ScriptError and would otherwise kill the task without a word.
      draw
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

  # Four corners plus a centre cross, driven through the real driver: if this
  # shows up, both the rendering and the whole driver path are working.
  def self_test
    m = $matrix
    m.clear
    m.set(1, 1); m.set(16, 1); m.set(1, 16); m.set(16, 16)
    i = 6
    while i <= 11
      m.set(i, 8)
      m.set(8, i)
      i += 1
    end
    m.show
    draw
    nil
  end

  def draw
    JS.global.renderPanel($panel.levels_hex)
    draw_notes
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

  # A melody plays over seconds in a task of its own while nothing else runs,
  # so the log needs a heartbeat that Run cannot stop.
  def start_monitor
    JS.global.setTimeout(MONITOR_MS) do
      begin
        draw_notes
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
    JS.global.fetch("examples/#{path}") do |response|
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
  public :draw, :report
end

Funicular.start(SimApp, container: 'app')
