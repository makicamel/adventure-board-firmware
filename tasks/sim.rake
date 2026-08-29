require "fileutils"

# Browser LED matrix simulator (sim/). See dev-docs/wasm-simulator/.
namespace :sim do
  desc "Serve the repository for the browser LED matrix simulator"
  task :server do
    port = ENV["PORT"] || "8080"
    puts "Serving #{MRUBY_ROOT}"
    puts "  open http://localhost:#{port}/sim/"
    # The repository root is the server root on purpose: the page loads
    # mrbgems/picoruby-is31fl3729/mrblib/is31fl3729.rb from this tree rather
    # than a copy, so that what runs in the browser is the real driver.
    if system("python3 --version", out: File::NULL, err: File::NULL)
      sh "python3 -m http.server #{port} --directory #{MRUBY_ROOT}"
    else
      # webrick is no longer a default gem, so this needs it installed.
      sh "ruby -run -e httpd #{MRUBY_ROOT} -p #{port}"
    end
  end

  desc "Run the headless check of the simulator core"
  task :test do
    FileUtils.cd MRUBY_ROOT do
      sh "bin/picoruby sim/test/panel_test.rb"
    end
  end
end
