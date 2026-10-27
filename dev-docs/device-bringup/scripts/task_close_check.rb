# 終わった Task が残る件（dev-docs/device-bringup/task-memory.md）を実機で確かめる。
#   1. Task を作って終わらせる → メモリが減ったまま。close すると戻る
#   2. いまの Speaker で短い音を何度も鳴らす → 鳴らした数だけ減る
#   3. 残った Player の Task を close する → 戻る
#   4. 直し方の案（曲を替えるときに前の Task を close する Speaker）で同じことをする → 減らない
# 2 と 4 で短い音が 20 回ずつ鳴る。
# ⚠ 4 は Speaker を書き換えたまま終わる。続けて別のプログラムを試す前に基板をリセットする。
require 'adventure_board'
GC.start

speaker = AdventureBoard.speaker
GC.start

N = 20
BEEP = "t240 o5 l32 c"

def report(label)
  GC.start
  st = PicoRubyVM.memory_statistics
  puts "#{label}: used=#{st[:used]} max_free=#{st[:max_free]} tasks=#{Task.list.size}"
end

# name の Task のうち、終わっている（DORMANT）ものの数
def dormant(name)
  n = 0
  Task.list.each do |t|
    n += 1 if t.name == name && t.status.to_s == "DORMANT"
  end
  n
end

def beep_n_times(speaker)
  i = 0
  while i < N
    speaker.play_mml(BEEP)
    while speaker.playing?
      sleep_ms 10
    end
    i += 1
  end
end

report "はじめ"

# 1. 素の Task
tasks = []
i = 0
while i < N
  tasks << Task.new { x = 1 }
  i += 1
end
sleep_ms 50   # 全部走り終わるのを待つ
report "1. Task を #{N} 個作って終わらせた"
tasks.each { |t| t.close }
tasks = nil
report "1. その #{N} 個を close した"

# 2. いまの Speaker（Player#start が曲ごとに Task を作り、誰も close しない）
beep_n_times(speaker)
speaker.stop
report "2. いまの Speaker で #{N} 回鳴らした"
puts "   終わったまま残っている Player の Task: #{dormant("MIDIBASE::MML::Player")}"

# 3. 残った Player の Task を片付ける
Task.list.each do |t|
  t.close if t.name == "MIDIBASE::MML::Player" && t.status.to_s == "DORMANT"
end
report "3. それを close した"

# 4. 直し方の案。lib/adventure_board/speaker.rb にこの 2 つを入れる
class Speaker
  def play_mml(mml, loop: false)
    halt
    unmute
    tracks = mml.is_a?(Array) ? mml : [mml]
    use_channels(tracks.size)
    sequence = MIDIBASE::MML::Sequence.new(tracks, loop: loop)
    player = MIDIBASE::MML::Player.new(
      sequence,
      clock: MIDIBASE::MML::InternalClock.new,
      output: @router.output(:mml)
    )
    @player = player
    # Player#start と同じことを、Task を手元に持ったまま
    @task = Task.new(name: "Speaker") { player.run }
    self
  end

  private def halt
    player = @player
    player.stop if player
    @player = nil
    task = @task
    task.close if task   # 走っていても終わっていても、止めてメモリを返す
    @task = nil
    ch = 0
    while ch < @channels
      all_notes_off(channel: ch)
      ch += 1
    end
    self
  end
end

beep_n_times(speaker)
report "4. 直し方の案で #{N} 回鳴らした（最後の 1 つは残る）"
puts "   終わったまま残っている Speaker の Task: #{dormant("Speaker")}"
speaker.stop
report "4. stop した"
