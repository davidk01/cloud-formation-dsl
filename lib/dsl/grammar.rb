require 'pegrb'
require 'dsl/ast'

module Dsl
module Grammar

  ##
  # Takes a pegrb expression, an expression that denotes the separator a resulting
  # node type and splices things together to create a list like object.

  def self.listify(expr, sep, node_type)
    (expr[:first] > (sep.ignore > expr).many.any[:rest]) >> ->(s) {
      [node_type.new(s[:first] + s[:rest])]
    }
  end

  @grammar = ::Grammar.rules do
    # fundamental building blocks
    ws, newline = one_of(' ', "\t"), one_of("\n", "\r\n", "\r")
    comment = (one_of('#') > cut! > (wildcard > !newline).many.any > wildcard > newline.many).ignore

    # used for port specifications
    integer = (one_of(/[1-9]/)[:first] > one_of(/\d/).many.any[:rest]) >> ->(s) {
      [Integer.new((s[:first][0].text + s[:rest].map(&:text).join).to_i)]
    }
    integer_list = Dsl::Grammar::listify(integer, m(', '), IntegerList)

    # key, value definitions
    key = (one_of(/[a-zA-Z]/).many > (one_of('-', ' ') >
     one_of(/[a-zA-Z0-9_\.]/).many).many.any)[:n] >> ->(s) {
      [s[:n].map(&:text).join]
    }
    double_quoted_value = (one_of('"') > cut! > ((wildcard > !one_of('"')).many.any >
     wildcard)[:quoted_value] > one_of('"')) >> ->(s) {
      [s[:quoted_value].map(&:text).join]
    }
    single_quoted_value = (one_of("'") > cut! > ((wildcard > !one_of("'")).many.any >
     wildcard)[:quoted_value] > one_of("'")) >> ->(s) {
     [s[:quoted_value].map(&:text).join]
    }
    quoted_value = single_quoted_value | double_quoted_value
    quoted_value_list = Dsl::Grammar::listify(quoted_value, m(', '), ValueList)

    # pair, pair list definitions
    generic_pair = (ws.many.any > key[:key] > m(': ') > cut! > quoted_value_list[:value]) >> ->(s) {
      [PairNode.new(s[:key].first, s[:value].first.value)]
    }
    generic_pair_list = Dsl::Grammar::listify(generic_pair, newline, PairList)

    # vm spec requires certain common things
    vm_spec = (quoted_value[:pool_name] > m(', ') > cut! > integer[:count] >
     (m(' instance ') | m(' instances ')) > cut! > m('with ') > cut! > quoted_value[:image_name]) >> ->(s) {
      [VMSpec.new(s[:pool_name].first, s[:count].first.value, s[:image_name].first)]
    }

    #named bootstrap sequences
    named_bootstrap_sequence = (m('bootstrap-sequence: ') > cut! > quoted_value[:sequence_name] >
     newline > generic_pair_list[:sequence]) >> ->(s) {
      [NamedBootstrapSequence.new(s[:sequence_name].first, s[:sequence].first.value)]
    }
    named_bootstrap_sequence_list = Dsl::Grammar::listify(named_bootstrap_sequence,
     newline.many, NamedBootstrapSequenceList)

    # common items used in various vm block definitions
    vm_flavor = ws.many.any > m('vm-flavor: ') > cut! > quoted_value[:flavor_name]
    bootstrap_sequence = ws.many.any > m('bootstrap-sequence:') > cut! > newline >
     generic_pair_list[:bootstrap_sequence]

    # load balancer definition
    load_balancer_block = (m('load-balancer: ') > cut! > vm_spec[:vm_spec] > newline >
     vm_flavor > newline > bootstrap_sequence) >> ->(s) {
      [LoadBalancerDefinitionBlock.new(s[:vm_spec].first, s[:flavor_name].first,
       s[:bootstrap_sequence].first.value)]
    }

    # service definitions
    service_def = (ws.many.any > m('service:') > cut! > newline > ws.many.any > m('port: ') > cut! > integer[:port] > cut! >
     newline > ws.many.any > m('healthcheck-endpoint: ') > cut! > quoted_value[:endpoint] > newline >
     ws.many.any > m('healthcheck-port: ') > cut! > integer[:endpoint_port]) >> ->(s) {
      [ServicePortDefinition.new(s[:port].first.value, s[:endpoint].first, s[:endpoint_port].first.value)]
    }
    service_defs = Dsl::Grammar::listify(service_def, newline, ServiceDefinitionList)

    # pool definition blocks
    pool_def_block = ((m('http') | m('tcp'))[:pool_type] > m('-pool: ') > cut! > vm_spec[:vm_spec] > cut! > newline >
     vm_flavor > cut! > newline > service_defs[:services] > cut! > newline >
     bootstrap_sequence) >> ->(s) {
      [(s[:pool_type].map(&:text).join =~ /tcp/ ? TCPPoolDefinition : HTTPPoolDefinition).new(s[:vm_spec].first,
       s[:flavor_name].first, s[:services].first.value, s[:bootstrap_sequence].first.value)]
    }
    pool_def_block_list = Dsl::Grammar::listify(pool_def_block, newline.many, PoolDefinitionList)

    #box definition blocks
    box_def_block = (m('box: ') > cut! > vm_spec[:vm_spec] > newline >
     vm_flavor > newline > bootstrap_sequence) >> ->(s) {
      [BoxDefinition.new(s[:vm_spec].first, s[:flavor_name].first,
       s[:bootstrap_sequence].first.value)]
    }
    box_def_block_list = Dsl::Grammar::listify(box_def_block, newline.many, BoxDefinitionList)

    # default key, value list
    defaults = (m('defaults:') > cut! > newline > generic_pair_list[:defaults]) >> ->(s) {
      [Defaults.new(s[:defaults])]
    }

    end_of_file = (ws | newline).many.any > !wildcard
    # so a cloud formation spec is just a default section, followed by named bootstrap
    # sequences, followed by some pool definitions and then followed by some box definitions
    # theoretically the entire thing can be empty
    rule :start, ((defaults > newline.many.ignore).any[:defaults] > # (defaults section)?
     (named_bootstrap_sequence_list > newline.many.ignore).any[:named_bootstrap_sequences] > # (bootstrap sequences)?
     (load_balancer_block[:load_balancer] > newline.many >
      pool_def_block_list[:pool_definitions] > newline.many).any > # (lb pools)?
     box_def_block_list.any[:box_definitions] > end_of_file) >> ->(s) {
      [:defaults, :named_bootstrap_sequence, :pool_definitions,
       :load_balancer, :box_definitions].each do |sym|
        s[sym] ||= []
      end
      if s[:load_balancer].empty? && s[:box_definitions].empty?
        raise StandardError, "Either pool definitions or box definitions must be non-empty."
      end
      [RawCloudFormation.new(s[:defaults].first.value, s[:named_bootstrap_sequences].first.value,
       s[:load_balancer].first, s[:pool_definitions].first, s[:box_definitions].first)]
    }

  end

  def self.parse(str); @grammar.parse(str); end

end
end
