require "fileutils"
require "shellwords"

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

  desc "Drive the simulator page in a headless browser and report what it shows"
  task :check, [:example] do |_t, args|
    compose = "docker compose -f #{Shellwords.escape("#{MRUBY_ROOT}/docker/compose.yml")}"
    env = "HOST_UID=#{Process.uid} HOST_GID=#{Process.gid}"
    unless system("docker image inspect picorubykaigi01-browser-check:latest",
                  out: File::NULL, err: File::NULL)
      sh "#{env} #{compose} build browser"
    end
    sh "#{env} #{compose} run --rm browser node /work/tools/browser-check/check.cjs #{args[:example]}"
  end

  desc "Rebuild the headless browser image"
  task :browser_image do
    sh "HOST_UID=#{Process.uid} HOST_GID=#{Process.gid} docker compose -f #{Shellwords.escape("#{MRUBY_ROOT}/docker/compose.yml")} build browser"
  end

  # The stock @picoruby/wasm-wasi has no VRAM, font or LED driver gems, so the
  # simulator falls back to the CDN without this and cannot draw text. Building
  # writes into the upstream npm directory, so the artifacts are copied out and
  # that directory is put back the way it was.
  desc "Build a PicoRuby.wasm with the drawing, font and LED gems into sim/vendor"
  task :wasm do
    emsdk = ENV["EMSDK_DIR"] || File.expand_path("~/emsdk")
    unless File.exist?("#{emsdk}/emsdk_env.sh")
      abort "emsdk not found at #{emsdk}. Set EMSDK_DIR to point at it."
    end
    compose = "docker compose -f #{Shellwords.escape("#{MRUBY_ROOT}/docker/compose.yml")}"
    env = "HOST_UID=#{Process.uid} HOST_GID=#{Process.gid} EMSDK_DIR=#{Shellwords.escape(emsdk)}"
    build = "source $EMSDK/emsdk_env.sh >/dev/null && " \
            "PICOBOARD_WASM=1 CONFIG=picoruby-wasm rake"
    sh %(#{env} #{compose} run --rm wasm bash -lc #{Shellwords.escape(build)})

    dist = "#{MRUBY_ROOT}/mrbgems/picoruby-wasm/npm/picoruby/dist"
    vendor = "#{MRUBY_ROOT}/sim/vendor"
    FileUtils.mkdir_p vendor
    %w[init.iife.js picoruby.js picoruby.wasm].each do |name|
      src = "#{dist}/#{name}"
      abort "#{src} was not produced" unless File.exist?(src)
      FileUtils.cp src, "#{vendor}/#{name}"
    end
    # The build writes into mrbgems/picoruby-wasm/npm, but everything it puts
    # there is already git-ignored, so nothing has to be put back.
    puts "sim/vendor is ready; the page will load it instead of the CDN."
  end

  desc "Run the headless check of the simulator core"
  task :test do
    FileUtils.cd MRUBY_ROOT do
      sh "bin/picoruby sim/test/panel_test.rb"
    end
  end
end
