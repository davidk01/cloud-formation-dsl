require 'dsl/version'
require 'dsl/grammar'

module Dsl

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
        bootstrap_sequence = pool.bootstrap_sequence.value
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

  def self.parse(str); Grammar.parse(str); end

end
