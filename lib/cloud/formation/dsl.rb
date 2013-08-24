require 'cloud/formation/dsl/version'
require 'pegrb'

module Cloud
module Formation
module Dsl

  @grammar = Grammar.rules do
    
  end

  def self.parse(str); @grammar.parse(str); end

end
end
end
