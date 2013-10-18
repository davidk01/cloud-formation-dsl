# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'dsl/version'

Gem::Specification.new do |spec|
  spec.name          = "cloud-formation-dsl"
  spec.version       = Dsl::VERSION
  spec.authors       = ["david karapetyan"]
  spec.email         = ["dkarapetyan@scriptcrafty.com"]
  spec.description   = %q{Simple DSL for describing pools of VMs.}
  spec.summary       = %q{Uses Pegrb to describe a simple DSL for describing pools of VMs.}
  spec.homepage      = "https://github.com/davidk01/cloud-formation-dsl"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "pry"
end
