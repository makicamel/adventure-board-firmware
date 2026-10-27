module LinkPong
  module Font
    GLYPHS = {
      "0" => ["###", "#.#", "#.#", "#.#", "###"],
      "1" => [".#.", "##.", ".#.", ".#.", "###"],
      "2" => ["###", "..#", "###", "#..", "###"],
      "3" => ["###", "..#", "###", "..#", "###"],
      "4" => ["#.#", "#.#", "###", "..#", "..#"],
      "5" => ["###", "#..", "###", "..#", "###"],
      "6" => ["###", "#..", "###", "#.#", "###"],
      "7" => ["###", "..#", "..#", "..#", "..#"],
      "8" => ["###", "#.#", "###", "#.#", "###"],
      "9" => ["###", "#.#", "###", "..#", "###"],
    }
    WIDTH  = 3
    HEIGHT = 5

    def self.width(text, scale = 1) = (text.size * (WIDTH + 1) - 1) * scale

    def self.draw(matrix, text, left, top, brightness, scale = 1)
      text.size.times do |i|
        rows = GLYPHS[text[i]]
        HEIGHT.times do |row|
          WIDTH.times do |column|
            next unless rows[row][column] == "#"
            x = left + (i * (WIDTH + 1) + column) * scale
            y = top + row * scale
            scale.times do |dy|
              scale.times { |dx| matrix.set(x + dx, y + dy, brightness) }
            end
          end
        end
      end
    end
  end
end
