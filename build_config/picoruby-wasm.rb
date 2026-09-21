MRuby::CrossBuild.new("picoruby-wasm#{ENV['PICORB_DEBUG'] ? '-debug' : ''}") do |conf|
  conf.generate_package_json_from_template(
    "#{MRUBY_ROOT}/mrbgems/picoruby-wasm/npm/picoruby/package.json.template",
    "#{MRUBY_ROOT}/mrbgems/picoruby-wasm/npm/picoruby/package.json"
  )
  conf.generate_package_json_from_template(
    "#{MRUBY_ROOT}/mrbgems/picoruby-wasm/npm/mrbc/package.json.template",
    "#{MRUBY_ROOT}/mrbgems/picoruby-wasm/npm/mrbc/package.json"
  )

  conf.toolchain :clang

  conf.cc.defines << "PICORB_PLATFORM_POSIX"
  conf.cc.defines << "PICORB_PLATFORM_WASM"
  conf.cc.defines << "MRB_TICK_UNIT=4"
  conf.cc.defines << "MRB_TIMESLICE_TICK_COUNT=1"
  conf.cc.defines << "MRB_32BIT"
  conf.cc.defines << "MRB_INT64"
  conf.cc.defines << "MRB_NO_BOXING"
  conf.cc.defines << "MRB_UTF8_STRING"

  conf.cc.command = 'emcc'
  conf.linker.command = 'emcc'
  conf.archiver.command = 'emar'

  conf.picoruby(alloc_estalloc: false)
  conf.gembox "mruby-posix"
  conf.gembox "stdlib"

  if ENV['PICORB_DEBUG']
    conf.cc.defines << "MRB_USE_DEBUG_HOOK"
    conf.gem gemdir: "#{MRUBY_ROOT}/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-binding"
  end
  conf.gem gemdir: "#{MRUBY_ROOT}/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-math"
  conf.gem core: 'picoruby-wasm'
  conf.gem core: 'picoruby-indexeddb'
  conf.gem core: 'picoruby-funicular'
  conf.gem core: 'picoruby-markdown'
  conf.gem core: 'picoruby-drb'
  conf.gem core: 'picoruby-sqlite3'

  # The picorubykaigi01-board simulator needs the drawing and font gems, which
  # the stock package leaves out, plus the LED driver. Guarded so that an
  # ordinary `rake wasm:build_prod` still produces the upstream package; see
  # `rake sim:wasm`.
  if ENV['PICOBOARD_WASM']
    conf.gem core: 'picoruby-vram'
    conf.gem core: 'picoruby-bdffont'
    conf.gem core: 'picoruby-shinonome'
    conf.gem core: 'picoruby-syntax-highlight'   # colours the simulator's code box
    # Keep this one last. Its mrblib opens with `require 'i2c'`, which the
    # browser does not have, so its gem init raises -- and mrb_open() gives up
    # on every gem after the one that raised, without a word. (The page loads
    # the driver's source itself, after the require shim in sim_panel.rb.)
    conf.gem core: 'picoruby-is31fl3729'
  end
end
