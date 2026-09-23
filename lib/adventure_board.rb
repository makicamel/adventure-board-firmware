# Board support for Adventure Board.
#
# This file is not a gem. It is meant to live on the device's filesystem as
# /lib/adventure_board.rb and be picked up by `require 'adventure_board'`, so
# that anyone can open it, read the pin numbers and change them. The register
# level work is in the picoruby-is31fl3729 gem; what is here is the part worth
# reading.
#
# Pin assignments come from
# ref/picorubykaigi01-board/docs/PicoBoard_BOM_pin_assignment_20260824.xlsx,
# which is machine-extracted from the board. docs/gpio_assignment.md is older
# and disagrees; do not use it.
#
# This file brings in Board, which is the pins and how to bring them up. The
# peripherals live one class per file beside it, and a program requires the
# ones it uses:
#
#   require 'adventure_board'
#   require 'adventure_board/led_matrix'
#
# That is not ceremony. Compiling Ruby on the device costs about six times the
# source size in contiguous heap and leaves about five times it resident, so
# loading the LED matrix in order to blink the status LED is a real price a
# program pays. Measurements in dev-docs/device-bringup/require-memory.md.

require 'adventure_board/board'

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
