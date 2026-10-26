require 'adventure_board'
GC.start

require_relative 'court'
require_relative 'ball'
require_relative 'paddle'
require_relative 'title'

matrix = AdventureBoard.matrix
LinkPong::Title.new(matrix).run
