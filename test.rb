require 'dsl'
Dsl.parse(File.read 'examples/formation').resolve_bootstrap_sequence_includes
