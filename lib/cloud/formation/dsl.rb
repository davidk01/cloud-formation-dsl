#require 'cloud/formation/dsl/version'
require 'pegrb'

module Cloud
module Formation
module Dsl

  # AST nodes
  class ValueNode < Struct.new(:value); end
  class Name < ValueNode; end
  class NameList < ValueNode; end
  class Integer < ValueNode; end
  class IntegerList < ValueNode; end

  @grammar = Grammar.rules do
    # fundamental building blocks
    ws, newline = one_of(' ', "\t"), one_of("\n", "\r\n", "\r")
    comma_space = (one_of(',') > ws.many.any).ignore

    # used for port specifications
    integer = (one_of(/[1-9]/)[:first] > one_of(/\d/).many.any[:rest]) >> ->(s) {
      [Integer.new((s[:first][0].text + s[:rest].map(&:text).join).to_i)]
    }
    integer_list = (integer[:head] > (comma_space > integer).many.any[:tail]) >> ->(s) {
      [IntegerList.new(s[:head] + s[:tail])]
    }

    # used for various values in pool definition blocks
    name = (one_of(/[a-zA-Z]/).many > (one_of('-') > 
     one_of(/[a-zA-Z]/).many).many.any)[:n] >> ->(s) {
      [Name.new(s[:n].map(&:text).join)]
    }
    name_list = (name[:head] > (comma_space > name).many.any[:tail]) >> ->(s) {
      [NameList.new(s[:head] + s[:tail])]
    }

    # some values need to be filepaths
    absolute_paths =

    rule :start, name_list | integer_list
  end

  def self.parse(str); @grammar.parse(str); end

end
end
end
