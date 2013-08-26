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
  class PairList < ValueNode; end
  class QuotedValueList < ValueNode; end
  class VMSpec < Struct.new(:name, :count, :image_name); end
  class NamedBootstrapSequence < Struct.new(:name, :sequence); end
  class NamedBootstrapSequenceList < ValueNode; end
  class PoolDefinition < Struct.new(:vm_spec, :flavor, :ports, :bootstrap_sequence); end
  class PoolDefinitionList < ValueNode; end
  class BoxDefinition < Struct.new(:vm_spec, :falvor, :bootstrap_sequence); end
  class BoxDefinitionList < ValueNode; end
  class Defaults < ValueNode; end

  ##
  # This is the final result of the parsing process and contains all the necessary
  # methods for going from an AST to something that can be plugged into a given
  # backend for spinning up instances, monitoring, remediation, etc.

  class RawCloudFormation < Struct.new(:defaults, :bootstrap_sequences, :pools, :boxes)

    ##
    # Go through the pool and box definitions and replace any 'include' nodes
    # with the sequences they reference. This should be an indempotent method
    # and at the end of it there should be no 'include' nodes left.

    def resolve_bootstrap_sequence_includes
      pools.value.each do |pool|
        bootstrap_sequence = pool_bootstrap_sequence.value
        bootstrap_sequence.map! do |pair_node|
          if pair_node.key == 'include' && (seq_names = pair_node.value.value)
            seq = bootstrap_sequences.value.select {|s| seq_names.include?(s.name)}
            unless seq.length == seq_names.length
              raise StandardError, "Named sequence does not exist: names = #{seq_names.join(', ')}."
            end
            seq.map {|named_seq| named_seq.sequence.value}.flatten
          else
            pair_node
          end
        end
        bootstrap_sequence.flatten!
      end
    end
  end

  def self.listify(expr, sep, node_type)
    (expr[:first] > (sep.ignore > expr).many.any[:rest]) >> ->(s) {
      [node_type.new(s[:first] + s[:rest])]
    }
  end

  @grammar = Grammar.rules do
    # fundamental building blocks
    ws, newline = one_of(' ', "\t"), one_of("\n", "\r\n", "\r")
    comment = (one_of('#') > (wildcard > !newline).many.any > wildcard > newline.many).ignore

    # used for port specifications
    integer = (one_of(/[1-9]/)[:first] > one_of(/\d/).many.any[:rest]) >> ->(s) {
      [Integer.new((s[:first][0].text + s[:rest].map(&:text).join).to_i)]
    }
    integer_list = Dsl::listify(integer, m(', '), IntegerList)

    # key, value definitions
    key = (one_of(/[a-zA-Z]/).many > (one_of('-', ' ') > 
     one_of(/[a-zA-Z0-9_\. ]/).many).many.any)[:n] >> ->(s) {
      [s[:n].map(&:text).join]
    }
    double_quoted_value = (one_of('"') > ((wildcard > !one_of('"')).many.any >
     wildcard)[:quoted_value] > one_of('"')) >> ->(s) {
      [s[:quoted_value].map(&:text).join]
    }
    single_quoted_value = (one_of("'") > ((wildcard > !one_of("'")).many.any >
     wildcard)[:quoted_value] > one_of("'")) >> ->(s) {
     [s[:quoted_value].map(&:text).join]
    }
    quoted_value = single_quoted_value | double_quoted_value
    quoted_value_list = Dsl::listify(quoted_value, m(', '), QuotedValueList)

    # pair, pair list definitions
    generic_pair = (ws.many.any > key[:key] > m(': ') > quoted_value_list[:value]) >> ->(s) {
      [PairNode.new(s[:key].first, s[:value].first)]
    }
    generic_pair_list = Dsl::listify(generic_pair, newline, PairList)

    # vm spec requires certain common things
    vm_spec = (quoted_value[:name] > m(', ') > integer[:count] >
     (m(' instance ') | m(' instances ')) > m('with ') > quoted_value[:image_name]) >> ->(s) {
      [VMSpec.new(s[:name].first, s[:count].first, s[:image_name].first)]
    }
 
    #named bootstrap sequences
    named_bootstrap_sequence = (m('bootstrap sequence: ') > quoted_value[:sequence_name] >
     newline > generic_pair_list[:sequence]) >> ->(s) {
      [NamedBootstrapSequence.new(s[:sequence_name].first, s[:sequence].first)]
    }
    named_bootstrap_sequence_list = Dsl::listify(named_bootstrap_sequence,
     newline.many, NamedBootstrapSequenceList)

    # pool definition blocks
    pool_def_block = (m('pool: ') > vm_spec[:vm_spec] > newline >
     ws.many.any > m('vm flavor: ') > quoted_value[:flavor_name] > newline >
     (ws.many.any > m('service ports: ') > integer_list[:ports] > newline).any >
     ws.many.any > m('bootstrap sequence:') > newline >
     generic_pair_list[:bootstrap_sequence]) >> ->(s) {
      [PoolDefinition.new(s[:vm_spec].first, 
       s[:flavor_name].first, (s[:ports] || []).first, 
       s[:bootstrap_sequence].first)]
    }
    pool_def_block_list = Dsl::listify(pool_def_block, newline.many, PoolDefinitionList)

    #box definition blocks
    box_def_block = (m('box: ') > vm_spec[:vm_spec] > newline >
     ws.many.any > m('vm flavor: ') > quoted_value[:flavor_name] > newline >
     ws.many.any > m('bootstrap sequence:') > newline >
     generic_pair_list[:bootstrap_sequence]) >> ->(s) {
      [BoxDefinition.new(s[:vm_spec].first, s[:flavor_name].first,
       s[:bootstrap_sequence].first)]
    }
    box_def_block_list = Dsl::listify(box_def_block, newline.many, BoxDefinitionList)

    # default key, value list
    defaults = (m('defaults:') > newline > generic_pair_list[:defaults]) >> ->(s) {
      [Defaults.new(s[:defaults])]
    }

    # so a cloud formation spec is just a default section, followed by named bootstrap
    # sequences, followed by some pool definitions and then followed by some box definitions
    # theoretically the entire thing can be empty
    rule :start, ((defaults[:defaults] > newline.many).any >
     (named_bootstrap_sequence_list[:named_bootstrap_sequences] > newline.many).any >
     (pool_def_block_list[:pool_definitions] > newline.many).any >
     box_def_block_list.any[:box_definitions]) >> ->(s) {
      RawCloudFormation.new(s[:defaults].first, s[:named_bootstrap_sequences].first,
       s[:pool_definitions].first, s[:box_definitions].first)
    }

  end

  def self.parse(str); @grammar.parse(str); end

  def self.pipeline(raw_ast)
    raw_ast.resolve_bootstrap_sequence_includes
  end

end
end
end
