require 'adventure_board'
GC.start

require_relative 'court'
require_relative 'ball'
require_relative 'paddle'
require_relative 'sound'
require_relative 'font'
require_relative 'title'
require_relative 'game'
require_relative 'result'

matrix = AdventureBoard.matrix
buttons = AdventureBoard.buttons
sound = LinkPong::Sound.new(AdventureBoard.speaker)
while true
  LinkPong::Title.new(matrix, buttons).run
  returns = LinkPong::Game.new(matrix, buttons, sound).run
  LinkPong::Result.new(matrix, buttons, sound, returns).run
end
