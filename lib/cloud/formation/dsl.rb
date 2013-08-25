#require 'cloud/formation/dsl/version'
require 'pegrb'
require 'pathname'

module Cloud
module Formation
module Dsl

  # AST nodes
  class ValueNode < Struct.new(:value); end
  class PairNode < Struct.new(:key, :value); end
  class Name < ValueNode; end
  class NameList < ValueNode; end
  class Integer < ValueNode; end
  class IntegerList < ValueNode; end
  class PoolHeader < Struct.new(:pool_size, :pool_name, :image_name); end
  class BoxHeader < Struct.new(:box_count, :name, :image_name); end
  class BootstrapSpec < Struct.new(:spec); end
  class GitSpec < BootstrapSpec; end
  class FileSpec < BootstrapSpec; end
  class DirectorySpec < BootstrapSpec; end
  class InlineBashSpec < BootstrapSpec; end
  class IncludeSpec < BootstrapSpec; end
  class BootstrapSpecs < Struct.new(:sequence_name, :specs); end

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
    name_list = (name[:head] > (comma_space > name).many.any[:tail]) >> ->(s) {
      [NameList.new(s[:head] + s[:tail])]
    }

    # some values need to be absolute paths
    path_sep = one_of('/').ignore
    absolute_path = (path_sep > name[:head] > (path_sep > name).many.any[:tail]) >> ->(s) {
      [Pathname.new('/' + s[:head][0].value + '/' + s[:tail].map(&:value).join('/'))]
    }

    # box definition component
    box_header = (m('box: ') > name[:box_name] > m(', ') >
     integer[:box_count] > (m(' instance with ') | m(' instances with ')) >
     name[:image_name] > ws.many.any > newline) >> ->(s) {
      [BoxHeader.new(s[:box_count].first, s[:box_name].first, s[:image_name].first)]
    }

    # pool definition block components
    pool_header = (m('pool: ') > name[:pool_name] > m(', ') >
     integer[:size] > (m(' instance with ') | m(' instances with ')) >
     name[:image_name] > ws.many.any > newline) >> ->(s) {
     [PoolHeader.new(s[:size].first, s[:pool_name].first, s[:image_name].first)]
    }

    # bootstrap specs
    bootstrap_type = m('git: ') | m('file: ') | m('inline bash: ') |
     m('directory: ') | m('include: ')
    bootstrap_spec = (bootstrap_type[:type] >
     ((wildcard > !newline).many > wildcard)[:spec]) >> ->(s) {
      type = s[:type].map(&:text).join
      spec = s[:spec].map(&:text).join
      case type
      when 'git: '
        [GitSpec.new(spec)]
      when 'file: '
        [FileSpec.new(spec)]
      when 'inline bash: '
        [InlineBashSpec.new(spec)]
      when 'directory: '
        [DirectorySpec.new(spec)]
      when 'include: '
        [IncludeSpec.new(spec)]
      end
    }
    bootstrap_spec_header = ws.many.any > m('bootstrap sequence:') >
      (one_of(' ') > name[:sequence_name]).any
    bootstrap_specs = (ws.many.any > bootstrap_spec[:first] >
     (newline.ignore > ws.many.any.ignore > bootstrap_spec).many.any[:rest]) >> ->(s) {
       [BootstrapSpecs.new((s[:sequence_name] || []).first, s[:first] + s[:rest])]
    }
    bootstrap_spec_list = bootstrap_spec_header.ignore > newline.ignore > bootstrap_specs

    # somewhat optional components, as in the "default:" section should define
    # values for these things which can then be overriden by specifying the value
    # in the block
    optional_component = (ws.many.any.ignore > (m('ssh key name: ') |
     m('pem file: ') | m('security groups: '))[:optional_key] >
     (name | absolute_path)[:optional_key_value]) >> ->(s) {
    }
    optional_component_list = (optional_component[:first] > (newline >
      optional_component).many.any[:rest]) >> ->(s) {
    }

    # pool definition
    pool_def_block = (pool_header[:header] >
     ws.many.any > m('vm flavor: ') > name[:flavor_name] > newline >
     (ws.many.any > m('service ports: ') > integer_list[:ports] > newline).any >
     bootstrap_spec_list[:bootstrap_spec]) >> ->(s) {
      header, flavor = s[:header].first, s[:flavor_name].first
      ports = s[:ports] || IntegerList.new([Integer.new(80), Integer.new(8080)])
      require 'pry'; binding.pry
    }

    pool_def_blocks = (pool_def_block[:first] >
     (newline > pool_def_block).many.any[:rest]) >> ->(s) {
     require 'pry'; binding.pry
    }
 
    rule :start, pool_def_block
  end

  def self.parse(str); @grammar.parse(str); end

end
end
end
