# The games under games/ go to the board as .mrb, compiled here.
#
#   rake games:mrb                 # games/*.rb -> dist/games/*.mrb
#   rake games:run[link_pong]      # send it to /home on the board, reboot, run it
#
# Only the mrbc built from this tree makes bytecode the firmware can load.

namespace :games do
  desc "Compile games/*.rb into dist/games/*.mrb for the board"
  task :mrb => "docker:ensure_image" do
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
