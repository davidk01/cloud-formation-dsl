require 'bundler/setup'
require 'rubygems'
require 'dsl'
require 'pry'

dsl = Dsl.parse(File.read 'examples/formation')
binding.pry
dsl.resolve_bootstrap_sequence_includes
