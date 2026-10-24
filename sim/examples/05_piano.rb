# チュートリアル 5: ボタンのピアノ。押しているあいだだけ音が出る。

require 'adventure_board'
GC.start

matrix = AdventureBoard.matrix
buttons = AdventureBoard.buttons
speaker = AdventureBoard.speaker

# ボタンと音の高さ。MIDI の番号で、60 が MML の o4 c（約 262Hz のド）。1 増えると半音上がる
KEYS = { left: 60, down: 62, right: 64, up: 65, b: 67, a: 69 }

speaker.reset
sounding = nil    # いま鳴っている音

while true
  note = nil
  KEYS.each do |name, n|
    note = n if buttons.pressed?(name)
  end

  if note != sounding
    speaker.note_off(sounding) if sounding   # 前の音を止める
    speaker.note_on(note) if note            # 新しい音を鳴らす
    sounding = note

    matrix.clear
    matrix.fill(0x30) if note                # 鳴っているあいだ光らせる
    matrix.show
  end
  sleep_ms 10
end
