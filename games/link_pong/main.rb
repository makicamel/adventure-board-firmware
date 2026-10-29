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
require_relative 'link'
require_relative 'match'
require_relative 'result'

matrix = AdventureBoard.matrix
buttons = AdventureBoard.buttons
sound = LinkPong::Sound.new(AdventureBoard.speaker)
menu = LinkPong::Menu.new(matrix, buttons)
link = nil
while true
  LinkPong::Title.new(matrix, buttons).run
  menu.run
  if menu.players == 1
    rally_length = LinkPong::Game.new(matrix, buttons, sound, menu.hard?).run
  else
    link ||= LinkPong::Link.new
    rally_length = LinkPong::Match.new(matrix, buttons, sound, link, menu.hard?).run
  end
  LinkPong::Result.new(matrix, buttons, sound, rally_length).run if rally_length
end
