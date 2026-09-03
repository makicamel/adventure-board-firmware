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
# The classes live in picorubykaigi01/ beside this file, one per class, and
# only Board is loaded here. The rest arrive when a program first asks for
# them, because on the device compiling Ruby is expensive enough that loading
# the LED matrix to blink the status LED can cost the program its memory.
# The measurements are in dev-docs/device-bringup/require-memory.md.

require 'picorubykaigi01/board'

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
