require 'adventure_board'
GC.start

require_relative 'screen'
require_relative 'court'
require_relative 'ball'
require_relative 'paddle'
require_relative 'sound'
require_relative 'font'
require_relative 'controls'
require_relative 'title'
require_relative 'menu'
require_relative 'game'
require_relative 'result'

matrix = AdventureBoard.matrix
buttons = AdventureBoard.buttons
sound = LinkPong::Sound.new(AdventureBoard.speaker)
menu = LinkPong::Menu.new(matrix, buttons)
while true
  LinkPong::Title.new(matrix, buttons).run
  menu.run
  returns = LinkPong::Game.new(matrix, buttons, sound, menu.hard?).run
  LinkPong::Result.new(matrix, buttons, sound, returns).run
end
