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
# This file brings in Board, which is the pins and how to bring them up, and
# AdventureBoard, which is what a program asks for its peripherals. The
# peripherals live one class per file beside it, and each of those requires
# this one, so a program names only the ones it uses:
#
#   require 'adventure_board/led_matrix'
#   matrix = AdventureBoard.matrix
#
# That is not ceremony. Compiling Ruby on the device costs about six times the
# source size in contiguous heap and leaves about five times it resident, so
# loading the LED matrix in order to blink the status LED is a real price a
# program pays. Measurements in dev-docs/device-bringup/require-memory.md.

require 'adventure_board/board'

# --- what a program calls ----------------------------------------------------
#
# A program takes each peripheral it uses into a variable of its own, so that
# reading the program says where `matrix` came from. (These used to be
# top-level methods, `matrix` and friends, which looked like variables with
# no assignment anywhere, and a program's own `board = []` quietly hid one.)
#
# `$board` is set by whoever brought the board up: nothing on the device, where
# the first call boots it; the page in the simulator, which hands in stand-ins.
# A program never has to know how the peripherals were built, and the same
# source runs in both places.
module AdventureBoard
  # The Board itself, for what is not below: its pins, and how it was built.
  def self.board
    $board ||= Board.boot
  end

  def self.matrix           # adventure_board/led_matrix
    board.matrix
  end

  def self.buttons          # adventure_board/buttons
    board.buttons
  end

  def self.speaker          # adventure_board/speaker
    board.speaker
  end

  def self.status_led       # adventure_board/status_led
    board.status_led
  end

  # GROVE-B (J5) as a plain UART, or as the board-to-board link.
  def self.grove_uart(baudrate: 115200)
    board.grove_uart(baudrate: baudrate)
  end

  def self.grove_link(role: :a, baudrate: nil)   # adventure_board/grove_link
    baudrate ? board.grove_link(role: role, baudrate: baudrate) : board.grove_link(role: role)
  end

  # GROVE-A (J4), the I2C one.
  def self.grove_i2c(frequency: 100_000)
    board.grove_i2c(frequency: frequency)
  end
end
