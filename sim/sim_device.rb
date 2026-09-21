# The board itself, over USB, from the page: its shell's output, and a way to
# put the code in the editor onto it and run it.
#
# This is page machinery, not something a sample calls. It talks to R2P2's own
# shell the way a person at a terminal would, plus the shell's file transfer:
# Ctrl-B at the prompt answers ACK and hands the line to PicoModem
# (mrbgems/picoruby-picomodem), which takes one FILE_WRITE and returns to the
# prompt. demo/www/terminal.html in picoruby-wasm speaks the same protocol.
#
# Everything the board sends arrives through JS::WebSerial#on_receive as binary
# strings. It is kept in one buffer: outside a transfer it is also shown as
# text, inside one it is where the reply frames are read from. (terminal.html
# reads frames with binary_capture_*, which only works alongside its xterm
# reader, so it is not used here.)
class DeviceLink
  STX = 0x02
  ACK = 0x06

  FILE_WRITE = 0x02
  CHUNK      = 0x04
  ABORT      = 0xFF
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
  LOG_LIMIT   = 6000
  RX_LIMIT    = 65536

  PATH = "/home/app.rb"

  def self.supported?
    JS::WebSerial.supported?
  rescue Exception
    false
  end

  # What `clear_program` leaves in PATH. R2P2 runs PATH at every start, so the
  # last program sent from this page starts again with the board; with this
  # in its place the board comes up idle, at its prompt.
  IDLE_PROGRAM = "# The simulator page cleared the program that was here.\n"

  def initialize
    @port = nil
    @rx = ""
    @log = ""
    @in_transfer = false
    @escape = false
    @wanted = false       # someone pressed connect and has not pressed disconnect
    @watching = false
  end

  # What the board printed, without its terminal escapes, trimmed to the tail.
  attr_reader :log

  def connected?
    !@port.nil?
  end

  # Opens the browser's port picker, so it has to run from a click.
  def connect
    attach(JS::WebSerial.connect(baud_rate: 115200))
    @wanted = true
    watch_for_return
    # An Enter brings the prompt back, which shows the link is alive.
    send_text("\r")
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
  # well). PATH is left alone: like switching the power off and on, the board
  # starts the program that is there again. USB drops with the restart: the
  # port goes away here and comes back through watch_for_return.
  def reboot
    raise "実機に接続されていません" unless @port
    interrupt
    send_text("reboot\r")
    nil
  end

  # Stops the program and puts a line that does nothing in its place, so that
  # the board no longer runs anything when it starts.
  def clear_program
    raise "実機に接続されていません" unless @port
    interrupt
    upload(IDLE_PROGRAM, PATH)
    wait_for_text("[PicoModem] write", TIMEOUT_MS)
    wait_for_prompt(TIMEOUT_MS)
    nil
  end

  # Stop whatever is running, write the code to PATH, and run it.
  def run(source)
    raise "実機に接続されていません" unless @port
    interrupt
    upload(source, PATH)
    wait_for_text("[PicoModem] write", TIMEOUT_MS)
    wait_for_prompt(TIMEOUT_MS)
    send_text("#{PATH}\r")
    nil
  end

  # Ctrl-C stops a running program; at the prompt it only clears the line.
  # Either way the prompt comes back, and Ctrl-B is only heard there.
  def interrupt
    @rx = ""
    send_text("\x03")
    wait_for_prompt(TIMEOUT_MS)
    nil
  end

  def upload(source, path)
    @in_transfer = true
    success = false
    begin
      enter_transfer
      send_frame(FILE_WRITE, [source.bytesize].pack("N") + path)
      expect_frame(FILE_ACK, "FILE_WRITE")
      offset = 0
      while offset < source.bytesize
        send_frame(CHUNK, source.byteslice(offset, CHUNK_SIZE).to_s)
        expect_frame(CHUNK_ACK, "CHUNK")
        offset += CHUNK_SIZE
      end
      payload = expect_frame(DONE_ACK, "DONE")
      status, crc = payload.unpack("CN")
      raise "書き込みに失敗しました (status #{status})" unless status == 0
      unless crc == CRC.crc32(source)
        raise "CRC が一致しません (board #{crc}, page #{CRC.crc32(source)})"
      end
      success = true
    ensure
      begin
        send_frame(ABORT, "") unless success
      rescue Exception
        nil
      end
      @in_transfer = false
    end
    nil
  end

  private

  def attach(port)
    @port = port
    @rx = ""
    port.on_receive { |bytes| receive(bytes) }
    port.on_disconnect { @port = nil }
    nil
  end

  # A port the page was once allowed to use can be opened again without the
  # picker, and the browser says when one appears. So a board that restarts,
  # or a cable put back, reconnects by itself -- unless disconnect was pressed.
  # Nothing is sent on the way back in: the board is still starting, and R2P2
  # listens for a key at that point.
  def watch_for_return
    return nil if @watching
    @watching = true
    JS::WebSerial._watch_connect_events
    JS.global.addEventListener("serial-port-connect") do |_event|
      Task.new(name: "device-return") do
        begin
          come_back
        rescue Exception => e
          JS.global[:console].error("実機の再接続に失敗しました: #{e.class}: #{e.message}")
        end
      end
    end
    nil
  end

  def come_back
    raw = JS::WebSerial._take_last_connected_port
    return nil if raw.nil? || !@wanted || @port
    port = JS::WebSerial.new(raw)
    port.open(baud_rate: 115200)
    attach(port)
    nil
  end

  def receive(bytes)
    return if bytes == true # the disconnect sentinel
    bytes = bytes.to_s
    @rx << bytes
    @rx = @rx.byteslice(@rx.bytesize - RX_LIMIT, RX_LIMIT).to_s if RX_LIMIT < @rx.bytesize
    append_log(bytes) unless @in_transfer
    nil
  end

  # Keeps printable text and newlines; drops CSI sequences (the line editor
  # redraws the prompt with them on every keystroke) and other controls.
  def append_log(bytes)
    out = ""
    i = 0
    n = bytes.bytesize
    while i < n
      c = bytes.getbyte(i)
      if @escape
        # ESC [ params final: the final byte is 0x40..0x7E
        @escape = false if c != 0x5B && 0x40 <= c && c <= 0x7E
      elsif c == 0x1B
        @escape = true
      elsif c == 0x0A
        out << "\n"
      elsif 0x20 <= c || c == 0x09
        out << bytes.byteslice(i, 1).to_s
      end
      i += 1
    end
    return nil if out.empty?
    # A new string, not <<: the page remembers the last one it showed and
    # compares, and an appended-to string would compare equal to itself.
    @log = @log + out
    @log = @log.byteslice(@log.bytesize - LOG_LIMIT, LOG_LIMIT).to_s if LOG_LIMIT < @log.bytesize
    nil
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

  def enter_transfer
    @rx = ""
    send_bytes(STX.chr)
    deadline = now_ms + TIMEOUT_MS
    while true
      at = @rx.index(ACK.chr)
      if at
        @rx = @rx.byteslice(at + 1, @rx.bytesize).to_s
        return nil
      end
      raise "実機が転送モードに入りません（ACK が来ない）" if deadline < now_ms
      sleep_ms 10
    end
  end

  def send_frame(cmd, payload)
    body = cmd.chr + payload
    send_bytes([STX, body.bytesize].pack("Cn") + body + [CRC.crc16(body)].pack("n"))
  end

  def expect_frame(want, what)
    cmd, payload = receive_frame
    if cmd == ERROR
      raise "実機がエラーを返しました (#{what}): #{payload}"
    end
    raise "予期しない応答 (#{what}): 0x#{cmd.to_s(16)}" unless cmd == want
    payload
  end

  def receive_frame
    deadline = now_ms + TIMEOUT_MS
    while true
      frame = take_frame
      return frame if frame
      raise "実機の応答がありません" if deadline < now_ms
      sleep_ms 10
    end
  end

  # One whole frame off the front of the buffer, or nil if it is not all here.
  def take_frame
    start = @rx.index(STX.chr)
    if start.nil?
      @rx = ""
      return nil
    end
    @rx = @rx.byteslice(start, @rx.bytesize).to_s if 0 < start
    return nil if @rx.bytesize < 3
    length = @rx.byteslice(1, 2).to_s.unpack("n")[0]
    total = 3 + length + 2
    return nil if @rx.bytesize < total
    body = @rx.byteslice(3, length).to_s
    crc = @rx.byteslice(3 + length, 2).to_s.unpack("n")[0]
    @rx = @rx.byteslice(total, @rx.bytesize).to_s
    raise "応答の CRC が一致しません" unless crc == CRC.crc16(body)
    [body.getbyte(0), body.byteslice(1, body.bytesize).to_s]
  end

  def wait_for_text(text, timeout_ms)
    deadline = now_ms + timeout_ms
    until @rx.include?(text)
      raise "実機の応答がありません（#{text} を待っています）" if deadline < now_ms
      sleep_ms 10
    end
    nil
  end

  def wait_for_prompt(timeout_ms)
    wait_for_text("$> ", timeout_ms)
    @rx = ""
    nil
  end

  def now_ms
    JS.global[:performance].now.to_f.to_i
  end
end
