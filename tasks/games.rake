# The games under games/ go to the board as .mrb, compiled here.
#
#   rake games:combine             # games/<name>/main.rb -> games/<name>.rb
#   rake games:mrb                 # games/*.rb -> dist/games/*.mrb
#   rake games:run[link_pong]      # send it to /home on the board, reboot, run it
#
# A game is written as files in games/<name>/, and main.rb lists them with
# require_relative. The board and the console both take one file, so
# combine puts each require_relative's file in its place (once) and writes
# games/<name>.rb, which is git-ignored.
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
      docker_compose_run("shell", "build/host/bin/mrbc", "-o", "dist/games/#{name}.mrb", "games/#{name}.rb")
    end
  end

  # Over the board's USB, with tools/r2p2dev.py (R2P2_PORT picks the port).
  # The reboot clears the heap the last run left in pieces, and skips app.rb.
  desc "Build a game, send it to the board, reboot it and run the game"
  task :run, [:name] => :mrb do |_t, args|
    name = args[:name] || "link_pong"
    mrb = "dist/games/#{name}.mrb"
    abort "#{mrb} was not built" unless File.exist?("#{MRUBY_ROOT}/#{mrb}")
    dev = "python3 #{Shellwords.escape("#{MRUBY_ROOT}/tools/r2p2dev.py")}"
    sh "#{dev} push #{Shellwords.escape("#{MRUBY_ROOT}/#{mrb}")} /home/#{name}.mrb"
    sh "#{dev} reboot"
    sh "#{dev} run /home/#{name}.mrb"
  end
end
