require 'pegrb'
require 'dsl/ast'

module Dsl
module Grammar

  def self.listify(expr, sep, node_type)
    (expr[:first] > (sep.ignore > expr).many.any[:rest]) >> ->(s) {
      [node_type.new(s[:first] + s[:rest])]
    }
  end

  @grammar = ::Grammar.rules do
    # fundamental building blocks
    ws, newline = one_of(' ', "\t"), one_of("\n", "\r\n", "\r")
    comment = (one_of('#') > (wildcard > !newline).many.any > wildcard > newline.many).ignore

    # used for port specifications
    integer = (one_of(/[1-9]/)[:first] > one_of(/\d/).many.any[:rest]) >> ->(s) {
      [Integer.new((s[:first][0].text + s[:rest].map(&:text).join).to_i)]
    }
    integer_list = Dsl::Grammar::listify(integer, m(', '), IntegerList)

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
    quoted_value_list = Dsl::Grammar::listify(quoted_value, m(', '), ValueList)

    # pair, pair list definitions
    generic_pair = (ws.many.any > key[:key] > m(': ') > quoted_value_list[:value]) >> ->(s) {
      [PairNode.new(s[:key].first, s[:value].first)]
    }
    generic_pair_list = Dsl::Grammar::listify(generic_pair, newline, PairList)

    # vm spec requires certain common things
    vm_spec = (quoted_value[:name] > m(', ') > integer[:count] >
     (m(' instance ') | m(' instances ')) > m('with ') > quoted_value[:image_name]) >> ->(s) {
      [VMSpec.new(s[:name].first, s[:count].first, s[:image_name].first)]
    }

    #named bootstrap sequences
    named_bootstrap_sequence = (m('bootstrap-sequence: ') > quoted_value[:sequence_name] >
     newline > generic_pair_list[:sequence]) >> ->(s) {
      [NamedBootstrapSequence.new(s[:sequence_name].first, s[:sequence].first)]
    }
    named_bootstrap_sequence_list = Dsl::Grammar::listify(named_bootstrap_sequence,
     newline.many, NamedBootstrapSequenceList)

    # common items used in various vm block definitions
    vm_flavor = ws.many.any > m('vm-flavor: ') > quoted_value[:flavor_name]
    bootstrap_sequence = ws.many.any > m('bootstrap-sequence:') > newline >
     generic_pair_list[:bootstrap_sequence]

    # load balancer definition
    load_balancer_block = (m('load-balancer: ') > vm_spec[:vm_spec] > newline >
     vm_flavor > newline >
     bootstrap_sequence) >> ->(s) {
      [LoadBalancerDefinitionBlock.new(s[:vm_spec].first, s[:flavor_name].first,
       s[:bootstrap_sequence].first)]
    }

    # pool definition blocks
    pool_def_block = (m('pool: ') > vm_spec[:vm_spec] > newline >
     vm_flavor > newline > 
     (ws.many.any > m('service-ports: ') > integer_list[:ports] > newline).any >
     bootstrap_sequence) >> ->(s) {
      [PoolDefinition.new(s[:vm_spec].first,
       s[:flavor_name].first, (s[:ports] || []).first,
       s[:bootstrap_sequence].first)]
    }
    pool_def_block_list = Dsl::Grammar::listify(pool_def_block, newline.many, PoolDefinitionList)

    #box definition blocks
    box_def_block = (m('box: ') > vm_spec[:vm_spec] > newline >
     vm_flavor > newline >
     bootstrap_sequence) >> ->(s) {
      [BoxDefinition.new(s[:vm_spec].first, s[:flavor_name].first,
       s[:bootstrap_sequence].first)]
    }
    box_def_block_list = Dsl::Grammar::listify(box_def_block, newline.many, BoxDefinitionList)

    # default key, value list
    defaults = (m('defaults:') > newline > generic_pair_list[:defaults]) >> ->(s) {
      [Defaults.new(s[:defaults])]
    }

    # so a cloud formation spec is just a default section, followed by named bootstrap
    # sequences, followed by some pool definitions and then followed by some box definitions
    # theoretically the entire thing can be empty
    rule :start, ((defaults > newline.many.ignore).any[:defaults] > # (defaults section)?
     (named_bootstrap_sequence_list > newline.many.ignore).any[:named_bootstrap_sequences] > # (bootstrap sequences)?
     (load_balancer_block[:load_balancer] > newline.many >
      pool_def_block_list[:pool_definitions] > newline.many).any > # (lb pools)?
     box_def_block_list.any[:box_definitions]) >> ->(s) {
      require 'pry'; binding.pry
      [:defaults, :named_bootstrap_sequence, :pool_definitions,
       :load_balancer, :box_definitions].each do |sym|
        s[sym] ||= []
      end
      if s[:load_balancer].empty? && s[:box_definitions].empty?
        raise StandardError, "Either pool definitions or box definitions must be non-empty."
      end
      require 'pry'; binding.pry
      RawCloudFormation.new(s[:defaults].first, s[:named_bootstrap_sequences].first,
       s[:pool_definitions].first, s[:load_balancer].first, s[:box_definitions].first)
    }

  end

  def self.parse(str); @grammar.parse(str); end

end
end
