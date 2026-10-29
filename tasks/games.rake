# The games under games/ go to the board as .mrb, compiled here.
#
#   rake games:combine             # games/<name>/main.rb -> games/<name>.rb
#   rake games:mrb                 # games/*.rb + lib/ -> dist/games/*.mrb
#   rake games:run                 # link_pong to every board plugged in, as /home/app.mrb
#   rake games:run[game]           # ... as /home/link_pong.mrb, and run it now
#   R2P2_PORT=/dev/cu.usbmodem1301 rake games:run   # only to that board
#
# A game is written as files in games/<name>/, and main.rb lists them with
# require_relative. The board and the console both take one file, so
# combine puts each require_relative's file in its place (once) and writes
# games/<name>.rb, which is git-ignored.
#
# The console has the board library loaded already, so games/<name>.rb keeps
# its `require 'adventure_board'`. The board would compile the library from
# /lib, part by part, which with a game in memory runs it out of heap. So
# the .mrb has that line replaced by the library itself, with only the parts
# the game asks AdventureBoard for: AdventureBoard.use finds them defined and
# reads nothing from /lib.
#
# Only the mrbc built from this tree makes bytecode the firmware can load.

def games_inline(path, seen)
  path = File.expand_path(path)
  return "" if seen[path]
  seen[path] = true
  File.read(path).gsub(/^require_relative ['"]([^'"]+)['"]\n/) do
    name = Regexp.last_match(1)
    games_inline(File.join(File.dirname(path), "#{name}.rb"), seen)
  end
end

# lib/adventure_board.rb with each `require 'adventure_board/...'` replaced by
# that file, once.
def games_library(path, seen)
  path = File.expand_path(path)
  return "" if seen[path]
  seen[path] = true
  File.read(path).gsub(/^require ['"](adventure_board\/[^'"]+)['"]\n/) do
    name = Regexp.last_match(1)
    games_library("#{MRUBY_ROOT}/lib/#{name}.rb", seen)
  end
end

# The parts a game uses: AdventureBoard.matrix -> lib/adventure_board/led_matrix.rb,
# read from the use(...) in each of AdventureBoard's methods.
def games_parts(source)
  lib = File.read("#{MRUBY_ROOT}/lib/adventure_board.rb")
  paths = lib.scan(/def self\.(\w+).*?\n\s+use\(:\w+, ['"]([^'"]+)['"]\)/).to_h
  source.scan(/AdventureBoard\.(\w+)/).flatten.uniq.filter_map { |name| paths[name] }
end

def games_for_board(source)
  require_line = "require 'adventure_board'\n"
  abort "a game must start with #{require_line.inspect}" unless source.include?(require_line)
  seen = {}
  library = games_library("#{MRUBY_ROOT}/lib/adventure_board.rb", seen)
  games_parts(source).each { |part| library += games_library("#{MRUBY_ROOT}/lib/#{part}.rb", seen) }
  source.sub(require_line, library)
end

# as is "app" (/home/app.mrb, run when the board starts) or "game"
# (/home/<name>.mrb, run now).
def games_send(name, as, port)
  mrb = "dist/games/#{name}.mrb"
  abort "#{mrb} was not built" unless File.exist?("#{MRUBY_ROOT}/#{mrb}")
  dev = "python3 #{Shellwords.escape("#{MRUBY_ROOT}/tools/r2p2dev.py")}"
  dev = "R2P2_PORT=#{Shellwords.escape(port)} #{dev}"
  local = Shellwords.escape("#{MRUBY_ROOT}/#{mrb}")
  sh("#{dev} reboot") { |ok| sh "#{dev} skip" unless ok }  # app で動いていると戻れないので、抜き差ししてもらう
  if as == "app"
    sh "#{dev} push #{local} /home/app.mrb"
    sh("#{dev} run reboot --wait 1") { }  # 再起動でポートが消えるので、終わり方は問わない
  else
    sh "#{dev} push #{local} /home/#{name}.mrb"
    sh "#{dev} reboot"
    sh "#{dev} run /home/#{name}.mrb"
  end
end

namespace :games do
  desc "Combine games/<name>/ into games/<name>.rb"
  task :combine do
    Dir["#{MRUBY_ROOT}/games/*/main.rb"].sort.each do |main|
      out = "#{File.dirname(main)}.rb"
      dir = "#{File.dirname(main).delete_prefix("#{MRUBY_ROOT}/")}/"
      header = "# 自動生成したファイルなので編集しないこと。#{dir} を直して rake games:combine で作り直す\n"
      File.write(out, header + games_inline(main, {}))
      puts "#{out.delete_prefix("#{MRUBY_ROOT}/")} <- #{dir}"
    end
  end

  desc "Compile games/*.rb into dist/games/*.mrb for the board"
  task :mrb => ["docker:ensure_image", :combine] do
    unless File.exist?("#{MRUBY_ROOT}/build/host/bin/mrbc")
      abort "build/host/bin/mrbc is missing; build the host once with `rake docker:shell` and `rake` in it."
    end
    FileUtils.mkdir_p "#{MRUBY_ROOT}/dist/games"
    Dir["#{MRUBY_ROOT}/games/*.rb"].sort.each do |path|
      name = File.basename(path, ".rb")
      File.write("#{MRUBY_ROOT}/dist/games/#{name}.rb", games_for_board(File.read(path)))
      docker_compose_run("shell", "build/host/bin/mrbc", "-o", "dist/games/#{name}.mrb", "dist/games/#{name}.rb")
    end
  end

  # Over the board's USB, with tools/r2p2dev.py, one board after another;
  # R2P2_PORT picks one board instead of all. As app, the board starts the
  # game by itself whenever it is turned on.
  # A reboot clears the heap the last run left in pieces, and skips app.rb:
  # one before sending, since a game that filled the heap leaves too little
  # to receive a file, and one after, since receiving it leaves pieces too.
  desc "Build a game and send it to every board plugged in, as app (default) or game"
  task :run, [:as, :name] => :mrb do |_t, args|
    as = args[:as] || "app"
    abort "as must be app or game, not #{as}" unless %w[app game].include?(as)
    ports = ENV["R2P2_PORT"] ? [ENV["R2P2_PORT"]] : `python3 #{Shellwords.escape("#{MRUBY_ROOT}/tools/r2p2dev.py")} ports`.split
    abort "no board is plugged in" if ports.empty?
    ports.each { |port| games_send(args[:name] || "link_pong", as, port) }
  end
end
