require 'adventure_board'
GC.start

require_relative 'court'
require_relative 'ball'
require_relative 'paddle'
require_relative 'title'
require_relative 'game'
require_relative 'result'

matrix = AdventureBoard.matrix
buttons = AdventureBoard.buttons
while true
  LinkPong::Title.new(matrix, buttons).run
  won = LinkPong::Game.new(matrix, buttons).run
  LinkPong::Result.new(matrix, buttons, won).run
end
