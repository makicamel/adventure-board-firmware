# The link from the page to a real board, over USB.
#
# The board's shell is shown in a terminal on the page (xterm.js), and the
# keys typed there go straight to it: R2P2's shell, irb and vim work as they
# do over any other serial console. What the board prints is read by the
# stock bridge in JavaScript and written into the terminal directly
# (JS::WebSerial#start_terminal_read); the Ruby side only watches from the
# side when it has to -- for the prompt, with the text capture, or for the
# frames of a file transfer, with the binary capture, which takes the bytes
# away from the terminal while it is on. This is how PicoRuby's own web
# console (picoruby-wasm/demo/www/terminal.html) does it.
#
# "実機で実行" writes the code to RUN_PATH and runs it, once. "app.rb にする"
# writes it to APP_PATH, which R2P2 runs every time the board starts: that
# is how a program lives on a board with no computer attached. The transfer
# is PicoModem's frames, which the board's shell enters on Ctrl-B.
class DeviceLink
  STX = 0x02
  ACK = 0x06

  FILE_READ  = 0x01
  FILE_WRITE = 0x02
  CHUNK      = 0x04
  ABORT      = 0xFF
  FILE_DATA  = 0x81
  FILE_ACK   = 0x82
  CHUNK_ACK  = 0x84
  DONE_ACK   = 0x8F
  ERROR      = 0xFE

  CHUNK_SIZE = 512
  # The board's stdin ring is small and its reader is not always waiting, so
  # the bytes go out in short pieces with a gap, as terminal.html does.
  TX_PIECE    = 32
  TX_GAP_MS   = 20
  TIMEOUT_MS  = 5000

  RUN_PATH = "/home/run.rb"   # what "実機で実行" runs; nothing runs it later
  OPS_PATH = "/home/lib_ops.rb"   # the page's file operations; removes itself
  OPS_DONE = "[lib_ops] done"
  # The start of what DeviceLink#file_ops sends. The board's File.rename
  # will not write over a file (it says so and returns), so the old one is
  # moved aside first and put back if the new one does not take its place.
  OPS_HEADER = <<~RUBY
    # Written by the console page. It removes itself.
    def remove_file(path)
      File.unlink(path) if File.exist?(path)
    rescue => e
      puts "rm \#{path}: \#{e.message}"
    end

    def replace_file(from, to)
      old = to + ".old"
      remove_file(old)
      File.rename(to, old) if File.exist?(to)
      File.rename(from, to)
      if File.exist?(to)
        remove_file(old)
      elsif File.exist?(old)
        File.rename(old, to)
      end
    rescue => e
      puts "mv \#{from}: \#{e.message}"
    end

  RUBY
  APP_PATH = "/home/app.rb"   # what R2P2 runs at every start

  # The firmware's record of the /lib it wrote. Gone, the firmware writes
  # /lib again at the next start (system_files.c).
  SYSTEM_STAMP = "/etc/adventure-board-files"

  # What `clear_app` leaves in APP_PATH: a board that starts with this comes
  # up idle, at its prompt.
  IDLE_PROGRAM = "# The simulator page cleared the program that was here.\n"

  def self.supported?
    JS::WebSerial.supported?
  rescue Exception
    false
  end

  # `terminal` is the xterm.js Terminal the board's output goes to.
  def initialize(terminal)
    @terminal = terminal
    @port = nil
    @busy = false        # a transfer or a command is using the line; keys wait
    @wanted = false      # someone pressed connect and has not pressed disconnect
    @watching = false
    @returning = false
    @probe = nil
    @seen_ports = nil
    @last_text = nil     # what the text capture held when the last wait ended
    @board_said_error = false   # the last transfer ended with the board's ERROR
  end

  def connected?
    !@port.nil?
  end

  # Keys from the terminal. Dropped while the page itself is talking to the
  # board, so a transfer is not interleaved with typing -- except the
  # terminal's answer to "where is the cursor?" (ESC [ row ; col R). The
  # shell's line editor asks that every time it redraws the line, and waits
  # up to 500ms for the answer, throwing away what else comes in meanwhile.
  def type(text)
    port = @port
    return nil if port.nil?
    return nil if @busy && !cursor_report?(text)
    port.write(text)
    nil
  end

  # Opens the browser's port picker, so it has to run from a click.
  def connect
    port = JS::WebSerial.connect(baud_rate: 115200)
    attach(port)
    raw_of(port)[:picorubyShell] = true   # the one that was picked: tried first when it comes back
    @wanted = true
    watch_for_return
    # An Enter brings the prompt back, which shows the link is alive.
    port.write("\r")
    @terminal.focus
    nil
  end

  def disconnect
    @wanted = false
    port = @port
    @port = nil
    port.close if port
    nil
  end

  # Stops the program and restarts the board with the shell's own `reboot`
  # (the watchdog, so the peripherals go back to their power-on state as
  # well): like switching the power off and on, so APP_PATH runs again if it
  # holds a program. USB drops with the restart: the port goes away here and
  # comes back through watch_for_return.
  def reboot
    talking do
      interrupt
      send_text("reboot\r")
    end
  end

  # Stop whatever is running, write the code to RUN_PATH, and run it.
  def run(source)
    talking do
      interrupt
      upload(source, RUN_PATH)
      send_text("#{RUN_PATH}\r")
    end
  end

  # Stops the program and makes the code the board's own: written to
  # APP_PATH and started right away, as it will be at every start from now.
  def install(source)
    talking do
      interrupt
      upload(source, APP_PATH)
      send_text("#{APP_PATH}\r")
    end
  end

  # Stops the program and puts a line that does nothing in APP_PATH, so that
  # the board no longer runs anything when it starts.
  def clear_app
    talking do
      interrupt
      upload(IDLE_PROGRAM, APP_PATH)
    end
  end

  # Brings the board's library up to what this page has. `files` is
  # [[path on the board, contents], ...]. Returns the paths it rewrote and the
  # .mrb files it removed; both empty means the board was up to date, and then
  # nothing is touched. Otherwise the board restarts at the end: what it has
  # already loaded is still in memory.
  #
  # Every changed file is written beside its old self first, as <path>.new,
  # and only once all of them are there are they moved into place. PicoModem
  # deletes a file before writing it, so writing over it directly would leave
  # the board without that file if the line dropped half way. A failure while
  # writing takes the .new files away again and leaves the library as it was.
  #
  # A .mrb beside a library file goes too: `require` reads it before the .rb,
  # so it would hide the new one.
  def update_library(files)
    changed = []
    shadows = []
    board_version = nil
    talking do
      interrupt
      i = 0
      while i < files.size
        path = files[i][0]
        text = download(path)
        board_version = DeviceLink.version_in(text) if path == "/lib/adventure_board.rb"
        changed << files[i] unless text == files[i][1]
        shadow = "#{path[0, path.size - 3]}.mrb"
        shadows << shadow if download(shadow)
        i += 1
      end
      unless changed.empty? && shadows.empty?
        stage(changed)
        ops = []
        i = 0
        while i < changed.size
          ops << [:replace, "#{changed[i][0]}.new", changed[i][0]]
          i += 1
        end
        i = 0
        while i < shadows.size
          ops << [:remove, shadows[i]]
          i += 1
        end
        file_ops(ops)
        # Read back rather than trust what the script said.
        i = 0
        while i < changed.size
          unless download(changed[i][0]) == changed[i][1]
            raise "#{changed[i][0]} を入れ替えられませんでした。［ライブラリを初期設定に戻す］で戻せます"
          end
          i += 1
        end
        i = 0
        while i < shadows.size
          raise "#{shadows[i]} を消せませんでした" if download(shadows[i])
          i += 1
        end
        send_text("reboot\r")
      end
    end
    rewritten = []
    i = 0
    while i < changed.size
      rewritten << changed[i][0]
      i += 1
    end
    [rewritten, shadows, board_version]
  end

  # AdventureBoard::VERSION as written in a copy of lib/adventure_board.rb,
  # or nil (the first firmware's library has none).
  def self.version_in(text)
    return nil unless text
    at = text.index('VERSION = "')
    return nil unless at
    from = at + 11
    to = text.index('"', from)
    to ? text[from, to - from] : nil
  end

  # Puts /lib back the way the firmware on the board wrote it: the firmware
  # writes it again at the next start when its stamp is gone. What the page
  # may have left there and the firmware does not -- a .new from an update
  # that stopped half way, a .mrb that would be loaded instead of the .rb --
  # is taken away first. `paths` are the library's files (/lib/...). Returns
  # the paths removed.
  def reset_library(paths)
    removed = []
    talking do
      interrupt
      i = 0
      while i < paths.size
        path = paths[i]
        candidates = ["#{path}.new", "#{path}.old", "#{path[0, path.size - 3]}.mrb"]
        j = 0
        while j < candidates.size
          removed << candidates[j] if download(candidates[j])
          j += 1
        end
        i += 1
      end
      gone = removed.dup
      gone << SYSTEM_STAMP if download(SYSTEM_STAMP)
      unless gone.empty?
        ops = []
        i = 0
        while i < gone.size
          ops << [:remove, gone[i]]
          i += 1
        end
        file_ops(ops)
        i = 0
        while i < gone.size
          raise "#{gone[i]} を消せませんでした" if download(gone[i])
          i += 1
        end
      end
      send_text("reboot\r")
    end
    removed
  end

  # A line in the terminal, as the link's own notes are: what stays there
  # once the status line has moved on (a restart replaces it).
  def log(text)
    note(text)
  end

  # `announced`: the browser said a port appeared (as opposed to the periodic
  # look), which is worth a line in the log even when nothing comes of it.
  def look_for_return(announced)
    return nil if !@wanted || @port || @returning
    come_back(announced)
  rescue Exception => e
    note("再接続に失敗しました: #{e.class}: #{e.message}")
    nil
  end

  private

  def cursor_report?(text)
    text.start_with?("\e[") && text.end_with?("R") && text.include?(";")
  end

  # Ownership of the line for the page's own conversations with the board:
  # keys wait, and the text capture is on so the prompt can be waited for.
  def talking
    raise "実機に接続されていません" unless @port
    raise "実機と通信中です" if @busy
    @busy = true
    begin
      watching_text { yield }
    ensure
      @busy = false
    end
    nil
  end

  # Ctrl-C stops a running program; at the prompt it only clears the line.
  # Either way the prompt comes back, and Ctrl-B is only heard there.
  def interrupt
    send_text("\x03")
    wait_for_prompt(TIMEOUT_MS)
  end

  def attach(port)
    @port = port
    port.start_terminal_read(@terminal)
    port.on_disconnect do
      @port = nil if @port == port
      @probe = nil if @probe == port
      note("接続が切れました")
    end
    nil
  end

  # The SerialPort behind a JS::WebSerial, which keeps it to itself; the
  # capture calls take that rather than the wrapper.
  def raw_of(port)
    port.instance_variable_get(:@js_port)
  end

  # --- watching the text -----------------------------------------------------

  # The text capture keeps a copy of what goes to the terminal from here on.
  def watching_text
    raw = raw_of(@port || @probe)
    JS::WebSerial.capture_start(raw)
    begin
      yield
    ensure
      begin
        JS::WebSerial.capture_stop(raw)
      rescue Exception
        nil
      end
    end
  end

  def wait_for_text(text, timeout_ms)
    wait_for_any([text], timeout_ms)
  end

  # Waits until the capture holds one of `texts`; returns that one.
  def wait_for_any(texts, timeout_ms)
    raw = raw_of(@port || @probe)
    deadline = now_ms + timeout_ms
    seen = nil
    got = ""
    while seen.nil?
      got = JS::WebSerial.capture_peek(raw).to_s
      i = 0
      while i < texts.size
        if got.include?(texts[i])
          seen = texts[i]
          break
        end
        i += 1
      end
      break if seen
      raise "実機の応答がありません（#{texts[0]} を待っています）" if deadline < now_ms
      sleep_ms 10
    end
    @last_text = got
    # Seen; start afresh so the next wait does not find this one again.
    JS::WebSerial.capture_stop(raw)
    JS::WebSerial.capture_start(raw)
    seen
  end

  def wait_for_prompt(timeout_ms)
    wait_for_text("$> ", timeout_ms)
  end

  # Replaces and removes files on the board: `ops` is a list of
  # [:replace, from, to] (from takes to's place) and [:remove, path].
  # Returns what the board printed.
  #
  # Not by typing `mv` and `rm` at the shell. R2P2's line editor, before it
  # redraws the line after each key, throws away input that has not been
  # read yet (IO.get_cursor_position), so the end of a long line is lost
  # whenever it arrives while the editor is at the start (V1, v2026.10.25).
  # The operations go over as a script, by PicoModem, and the line that runs
  # it is short enough to arrive in one piece, like "実機で実行"'s.
  def file_ops(ops)
    script = OPS_HEADER
    i = 0
    while i < ops.size
      op = ops[i]
      if op[0] == :replace
        script += "replace_file(#{op[1].inspect}, #{op[2].inspect})\n"
      else
        script += "remove_file(#{op[1].inspect})\n"
      end
      i += 1
    end
    script += "File.unlink(#{OPS_PATH.inspect})\nputs #{OPS_DONE.inspect}\n"
    upload(script, OPS_PATH)
    send_text("#{OPS_PATH}\r")
    wait_for_text(OPS_DONE, TIMEOUT_MS)
    out = @last_text.to_s
    # The prompt may have come in with the mark, and the capture is fresh.
    after = out[(out.index(OPS_DONE) || 0) + OPS_DONE.size, out.size].to_s
    wait_for_prompt(TIMEOUT_MS) unless after.include?("$> ")
    out
  end

  # --- transfer --------------------------------------------------------------

  def upload(source, path)
    raw = raw_of(@port)
    success = false
    @board_said_error = false
    begin
      enter_transfer(raw)
      send_frame(FILE_WRITE, [source.bytesize].pack("N") + path)
      expect_frame(raw, FILE_ACK, "FILE_WRITE")
      offset = 0
      while offset < source.bytesize
        send_frame(CHUNK, source.byteslice(offset, CHUNK_SIZE).to_s)
        expect_frame(raw, CHUNK_ACK, "CHUNK")
        offset += CHUNK_SIZE
      end
      payload = expect_frame(raw, DONE_ACK, "DONE")
      status, crc = payload.unpack("CN")
      raise "書き込みに失敗しました (status #{status})" unless status == 0
      unless crc == CRC.crc32(source)
        raise "CRC が一致しません (board #{crc}, page #{CRC.crc32(source)})"
      end
      success = true
      # The shell prints "[PicoModem] write ..." and its prompt as it comes
      # back, and the first of that may already be in the binary capture. It
      # is all read from there, up to the prompt, and shown in the terminal;
      # switching captures in between would lose whatever fell in the gap.
      tail = read_until(raw, "$> ")
    ensure
      # A board that answered ERROR has already left PicoModem; an ABORT now
      # would start with STX and take it straight back in.
      begin
        send_frame(ABORT, "") unless success || @board_said_error
      rescue Exception
        nil
      end
      begin
        JS::WebSerial.binary_capture_stop(raw)
      rescue Exception
        nil
      end
    end
    # Without the shell's "where is the cursor?" (ESC [6n): it has long since
    # stopped waiting, and the terminal's answer would reach the board in the
    # middle of whatever the page sends next -- inside the next transfer, it
    # ends the transfer.
    @terminal.write(tail.split("\e[6n").join) if tail
    nil
  end

  # The contents of a file on the board, or nil when there is none. The
  # shell's "[PicoModem] read ..." and its prompt are read off here and not
  # shown: a look at a file is not something to report in the terminal.
  def download(path)
    raw = raw_of(@port)
    data = nil
    begin
      enter_transfer(raw)
      send_frame(FILE_READ, path)
      buf = ""
      first = true
      while true
        cmd, payload = receive_frame(raw)
        if cmd == FILE_DATA
          # The first piece starts with the file's size, which is not needed.
          payload = payload.byteslice(4, payload.bytesize - 4).to_s if first
          first = false
          buf << payload
          send_frame(CHUNK_ACK, 0.chr)
        elsif cmd == DONE_ACK
          status, crc = payload.unpack("CN")
          raise "読み出しに失敗しました (#{path}, status #{status})" unless status == 0
          raise "CRC が一致しません（#{path} の読み出し）" unless crc == CRC.crc32(buf)
          data = buf
          break
        elsif cmd == ERROR
          break if payload.start_with?("File not found")
          raise "実機がエラーを返しました (#{path} の読み出し): #{payload}"
        else
          raise "予期しない応答 (#{path} の読み出し): 0x#{cmd.to_s(16)}"
        end
      end
      read_until(raw, "$> ")
    ensure
      begin
        JS::WebSerial.binary_capture_stop(raw)
      rescue Exception
        nil
      end
    end
    data
  end

  # Writes every [path, contents] to <path>.new. If one fails, the ones
  # already written are removed again, as far as the board still answers.
  def stage(files)
    written = 0
    begin
      while written < files.size
        upload(files[written][1], "#{files[written][0]}.new")
        written += 1
      end
    rescue Exception => e
      begin
        # The prompt after a failed transfer may have gone by inside the
        # binary capture, so ask for a fresh one rather than wait for it.
        interrupt
        ops = []
        i = 0
        while i < written
          ops << [:remove, "#{files[i][0]}.new"]
          i += 1
        end
        file_ops(ops) unless ops.empty?
      rescue Exception => cleanup
        # Left behind, a .new is only clutter: nothing loads it.
        note("書きかけの .new を消せませんでした: #{cleanup.message}")
      end
      raise "#{e.message}（ライブラリは変えていません）"
    end
    nil
  end

  def read_until(raw, text)
    buf = ""
    deadline = now_ms + TIMEOUT_MS
    until buf.include?(text)
      chunk = JS::WebSerial.binary_capture_read(raw, 4096)
      if chunk && 0 < chunk.bytesize
        buf << chunk
      else
        raise "実機の応答がありません（#{text} を待っています）" if deadline < now_ms
        sleep_ms 10
      end
    end
    buf
  end

  # Ctrl-B at the prompt; the board answers ACK and speaks frames from then
  # on. The binary capture is on from before the Ctrl-B, so the ACK and
  # everything after it are kept from the terminal.
  def enter_transfer(raw)
    JS::WebSerial.binary_capture_start(raw)
    send_bytes(STX.chr)
    deadline = now_ms + TIMEOUT_MS
    while true
      b = JS::WebSerial.binary_capture_read(raw, 1)
      if b && 0 < b.bytesize
        return nil if b.getbyte(0) == ACK
        next
      end
      raise "実機が転送モードに入りません（ACK が来ない）" if deadline < now_ms
      sleep_ms 10
    end
  end

  def send_frame(cmd, payload)
    body = cmd.chr + payload
    send_bytes([STX, body.bytesize].pack("Cn") + body + [CRC.crc16(body)].pack("n"))
  end

  def expect_frame(raw, want, what)
    cmd, payload = receive_frame(raw)
    if cmd == ERROR
      @board_said_error = true
      raise "実機がエラーを返しました (#{what}): #{payload}"
    end
    raise "予期しない応答 (#{what}): 0x#{cmd.to_s(16)}" unless cmd == want
    payload
  end

  # One frame: STX, length (2 bytes), body, CRC16. Bytes before the STX are
  # what the shell was still printing, and are skipped.
  def receive_frame(raw)
    deadline = now_ms + TIMEOUT_MS
    while true
      b = JS::WebSerial.binary_capture_read(raw, 1)
      if b && 0 < b.bytesize
        break if b.getbyte(0) == STX
        next
      end
      raise "実機の応答がありません（フレーム待ち）" if deadline < now_ms
      sleep_ms 10
    end
    length = read_exact(raw, 2).unpack("n")[0]
    rest = read_exact(raw, length + 2)
    body = rest.byteslice(0, length).to_s
    crc = rest.byteslice(length, 2).to_s.unpack("n")[0]
    raise "CRC が一致しません（受信フレーム）" unless crc == CRC.crc16(body)
    [body.getbyte(0), body.byteslice(1, length - 1).to_s]
  end

  def read_exact(raw, n)
    buf = ""
    deadline = now_ms + TIMEOUT_MS
    while buf.bytesize < n
      chunk = JS::WebSerial.binary_capture_read(raw, n - buf.bytesize)
      if chunk && 0 < chunk.bytesize
        buf << chunk
        deadline = now_ms + TIMEOUT_MS
      else
        raise "実機の応答が途中で止まりました" if deadline < now_ms
        sleep_ms 10
      end
    end
    buf
  end

  def send_text(text)
    send_bytes(text)
  end

  def send_bytes(data)
    port = @port
    raise "実機との接続が切れました" unless port
    offset = 0
    while offset < data.bytesize
      port.write(data.byteslice(offset, TX_PIECE).to_s)
      offset += TX_PIECE
      sleep_ms TX_GAP_MS if offset < data.bytesize
    end
    port.drain.await
    nil
  end

  # --- coming back -------------------------------------------------------------

  # A port the page was once allowed to use can be opened again without the
  # picker, and the browser says when one appears. So a board that restarts,
  # or a cable put back, reconnects by itself -- unless disconnect was pressed.
  #
  # Which port is not taken from the event: the board has three (shell,
  # debug, MIDI), they come up together, and the page may have been allowed
  # more than one of them over time. Every allowed port is tried, and the one
  # that shows the shell's prompt is kept. Nothing is typed at a board that is
  # still starting: its own boot text ends in the prompt, and only a port that
  # stays silent gets an Enter.
  def watch_for_return
    return nil if @watching
    @watching = true
    JS::WebSerial._watch_connect_events
    # A block given to Task.new (or to an event listener) does not run with
    # this object as self, so the link is handed in by name.
    link = self
    JS.global.addEventListener("serial-port-connect") do |_event|
      JS::WebSerial._take_last_connected_port   # not used; cleared so it does not pile up
      Task.new(name: "device-return") do
        sleep_ms 1000                            # the other two ports are enumerating too
        link.look_for_return(true)
      end
    end
    # And a look every few seconds regardless, in case the browser's notice
    # does not come.
    Task.new(name: "device-watch") do
      while true
        sleep_ms 3000
        link.look_for_return(false)
      end
    end
    nil
  end

  def come_back(announced)
    @returning = true
    ports = JS.global[:navigator][:serial].getPorts.await
    n = ports[:length].to_i
    if n != @seen_ports
      @seen_ports = n
      note("ブラウザが許可済みとして持っているポート: #{n} 本")
    end
    if announced || 0 < n
      note("#{announced ? 'ポートが戻ってきました。' : ''}許可済みの #{n} 本からシェルを探します")
    end
    list = ordered(ports, n)
    i = 0
    while i < n && @port.nil?
      try_port(i, list[i])
      i += 1
    end
    if @port
      note("つなぎ直しました")
    elsif 0 < n
      note("シェルのポートが見つかりませんでした。数秒後にもう一度探します")
    end
    nil
  ensure
    @returning = false
  end

  # The port that was the shell last time is tried first: the browser hands
  # out the same object for the same port, so after the first return the
  # right one is found at once instead of after the others' time-outs. The
  # object is marked rather than remembered, because every look at it from
  # here is a new wrapper and two wrappers never compare equal.
  def ordered(ports, n)
    list = []
    i = 0
    while i < n
      raw = ports[i]
      if raw[:picorubyShell]
        list.unshift(raw)
      else
        list << raw
      end
      i += 1
    end
    list
  end

  # What R2P2 prints as it starts, before any prompt. A board whose app.rb
  # runs on and on (a program sent from this page, say) never gets to the
  # prompt, but its boot text still says which port is the shell.
  BOOT_TEXT = ["$> ", "Loading ", "Press 's'", "Starting shell"]

  # Keeps the port if the shell shows up on it: its boot text or prompt
  # within a boot's worth of time, or a prompt right after an Enter. Failing
  # both, the port that was the shell before is kept anyway -- a program is
  # probably running on it, and typing at it or Ctrl-C will tell. A port
  # that is being tried is read into the terminal like the real one, so the
  # boot log shows.
  def try_port(i, raw)
    port = JS::WebSerial.new(raw)
    begin
      port.open(baud_rate: 115200)
    rescue Exception => e
      note("ポート #{i + 1}: 開けません（#{e.message}）")
      return nil
    end
    @probe = port
    port.start_terminal_read(@terminal)
    port.on_disconnect do
      @port = nil if @port == port
      @probe = nil if @probe == port
    end
    ok = false
    watching_text do
      ok = seen_within(BOOT_TEXT, 10_000)
      unless ok
        port.write("\r")
        ok = seen_within(["$> "], 2_000)
      end
    end
    @probe = nil
    if !ok && raw[:picorubyShell]
      ok = true
      note("ポート #{i + 1}: 応答はありませんが、前にシェルだったポートなのでつなぎます（プログラムが動いているのかもしれません）")
    end
    if ok
      @port = port
      raw[:picorubyShell] = true
      note("ポート #{i + 1}: シェルです")
    else
      note("ポート #{i + 1}: 応答なし")
      port.close
    end
    nil
  end

  def seen_within(texts, timeout_ms)
    wait_for_any(texts, timeout_ms)
    true
  rescue Exception
    false
  end

  # A line of the page's own in the terminal, dim, so it is not mistaken for
  # something the board printed.
  def note(text)
    @terminal.write("\r\n\e[2m[接続] #{text}\e[0m\r\n")
    puts "[device] #{text}"
    nil
  end

  def now_ms
    JS.global[:performance].now.to_f.to_i
  end

  public :look_for_return   # called from the tasks above
end
