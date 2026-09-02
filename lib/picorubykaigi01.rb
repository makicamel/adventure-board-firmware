# Board support for picorubykaigi01-board.
#
# This file is not a gem. It is meant to live on the device's filesystem as
# /lib/picorubykaigi01.rb and be picked up by `require 'picorubykaigi01'`, so
# that anyone can open it, read the pin numbers and change them. The register
# level work is in the picoruby-is31fl3729 gem; what is here is the part worth
# reading.
#
# Pin assignments come from
# ref/picorubykaigi01-board/docs/PicoBoard_BOM_pin_assignment_20260824.xlsx,
# which is machine-extracted from the board. docs/gpio_assignment.md is older
# and disagrees; do not use it.
#
# The classes live in picorubykaigi01/ beside this file, one per class. That
# split is not decoration: PicoRuby compiles Ruby source on the device, and
# Kernel#require gives each file its own Sandbox which is torn down afterwards,
# so the compiler's memory is returned between files. As one 15KB file this
# library ran the board out of contiguous heap and hard-faulted it; see
# dev-docs/device-bringup/require-memory.md.

require 'picorubykaigi01/board'
require 'picorubykaigi01/led_matrix'
require 'picorubykaigi01/speaker'
require 'picorubykaigi01/status_led'
require 'picorubykaigi01/buttons'

# --- what a program calls ----------------------------------------------------
#
# `$board` is set by whoever brought the board up: /etc/init.d on the device,
# the page in the simulator. A program never has to know how the peripherals
# were built, and the same source runs in both places.
#
# Top-level defs, which land on Object. CRuby would make them private; mruby
# leaves them public, and either way they are reachable from anywhere with an
# implicit receiver, including inside a Task.

def board
  $board ||= Board.boot
end

def matrix
  board.matrix
end

def buttons
  board.buttons
end

def speaker
  board.speaker
end
