#require 'cloud/formation/dsl/version'
require 'pegrb'
require 'pathname'

module Cloud
module Formation
module Dsl

  # AST nodes
  class ValueNode < Struct.new(:value); end
  class Name < ValueNode; end
  class NameList < ValueNode; end
  class Integer < ValueNode; end
  class IntegerList < ValueNode; end
  class PoolHeader < Struct.new(:pool_size, :pool_name, :image_name); end
  class BootstrapSpec < Struct.new(:spec); end
  class GitSpec < BootstrapSpec; end
  class FileSpec < BootstrapSpec; end
  class DirectorySpec < BootstrapSpec; end
  class InlineBashSpec < BootstrapSpec; end
  class BootstrapSpecs < ValueNode; end

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

    # pool definition block components
    pool_header = (m('pool: ') > integer[:size] > m(' of ') > one_of("'") >
     name[:pool_name] > one_of("'") > m(' with ') > one_of("'") >
     name[:image_name] > one_of("'") > ws.many.any > newline) >> ->(s) {
     [PoolHeader.new(s[:size].first, s[:pool_name].first, s[:image_name].first)]
    }

    # bootstrap specs
    bootstrap_type = m('git: ') | m('file: ') | m('inline bash: ') | m('directory: ')
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
      end
    }
    bootstrap_spec_header = ws.many.any > m('bootstrap:')
    bootstrap_specs = (ws.many.any > bootstrap_spec[:first] >
     (newline.ignore > ws.many.any.ignore > bootstrap_spec).many.any[:rest]) >> ->(s) {
       [BootstrapSpecs.new(s[:first] + s[:rest])]
    }
    bootstrap_spec_list = bootstrap_spec_header.ignore > newline.ignore > bootstrap_specs

    # pool definition
    pool_def_block = (pool_header[:header] >
     ws.many.any > m('vm flavor: ') > name[:flavor_name] > newline >
     (ws.many.any > m('service ports: ') > integer_list[:ports] > newline).any >
     bootstrap_spec_list[:bootstrap_spec]) >> ->(s) {
      header, flavor = s[:header].first, s[:flavor_name].first
      ports = s[:ports] || IntegerList.new([Integer.new(80), Integer.new(8080)])
      require 'pry'; binding.pry
    }
 
    rule :start, pool_def_block
  end

  def self.parse(str); @grammar.parse(str); end

end
end
end
