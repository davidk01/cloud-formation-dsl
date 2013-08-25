#require 'cloud/formation/dsl/version'
require 'pegrb'

module Cloud
module Formation
module Dsl

  # AST nodes
  class ValueNode < Struct.new(:value); end
  class PairNode < Struct.new(:key, :value); end
  class Integer < ValueNode; end
  class IntegerList < ValueNode; end
  class Name < ValueNode; end
  class PairList < ValueNode; end
  class QuotedValue < ValueNode; end
  class VMSpec < Struct.new(:name, :count, :image_name); end

  @grammar = Grammar.rules do
    # fundamental building blocks
    ws, newline = one_of(' ', "\t"), one_of("\n", "\r\n", "\r")
    comma_space = (one_of(',') > ws.many.any).ignore

    comment = (one_of('#') > (wildcard > !newline).many.any > wildcard > newline.many).ignore

    # used for port specifications
    integer = (one_of(/[1-9]/)[:first] > one_of(/\d/).many.any[:rest]) >> ->(s) {
      [Integer.new((s[:first][0].text + s[:rest].map(&:text).join).to_i)]
    }
    integer_list = (integer[:head] > (comma_space > integer).many.any[:tail]) >> ->(s) {
      [IntegerList.new(s[:head] + s[:tail])]
    }

    # used for various values in pool definition blocks
    name = (one_of(/[a-zA-Z]/).many > (one_of('-', ' ') > 
     one_of(/[a-zA-Z0-9_\. ]/).many).many.any)[:n] >> ->(s) {
      [Name.new(s[:n].map(&:text).join)]
    }

    # some values need to be absolute paths and some need to be bash command sequences
    double_quoted_value = (one_of('"') > ((wildcard > !one_of('"')).many.any >
     wildcard)[:quoted_value] > one_of('"')) >> ->(s) {
      [QuotedValue.new(s[:quoted_value].map(&:text).join)]
    }
    single_quoted_value = (one_of("'") > ((wildcard > !one_of("'")).many.any >
     wildcard)[:quoted_value] > one_of("'")) >> ->(s) {
     [QuotedValue.new(s[:quoted_value].map(&:text).join)]
    }
    quoted_value = single_quoted_value | double_quoted_value
    quoted_value_list = quoted_value[:first] >
     (m(', ').ignore > quoted_value).many.any[:rest] >> ->(s) {
      [QuotedValueList.new(s[:first] + s[:rest])]
    }

    generic_pair = (ws.many.any > name[:key] > m(': ') > quoted_value_list[:value]) >> ->(s) {
      [PairNode.new(s[:key].first, s[:value].first)]
    }
    generic_pair_list = (generic_pair[:first] >
     (newline.ignore > generic_pair).many.any[:rest]) >> ->(s) {
      [PairList.new(s[:first] + s[:rest])]
    }

    vm_spec = (quoted_value[:name] > m(', ') > integer[:count] >
     (m(' instance ') | m(' instances ')) > m('with ') > quoted_value[:image_name]) >> ->(s) {
      [VMSpec.new(s[:name].first, s[:count].first, s[:image_name].first)]
    }
 
    #TODO: named bootstrap sequence

    # pool definition blocks
    pool_def_block = (m('pool: ') > vm_spec[:vm_spec] > newline >
     ws.many.any > m('vm flavor: ') > quoted_value[:flavor_name] > newline >
     (ws.many.any > m('service ports: ') > integer_list[:ports] > newline).any >
     ws.many.any > m('bootstrap sequence:') > newline > generic_pair_list) >> ->(s) {
      [PoolDef.new]
    }
    pool_def_block_list = (pool_def_block[:first] >
     (newline.ignore > pool_def_block).many.any[:rest]) >> ->(s) {
      [PoolDefList.new(s[:first] + s[:rest])]
    }

    #TODO: box definition sequence

    rule :start, pair_list
  end

  def self.parse(str); @grammar.parse(str); end

end
end
end
