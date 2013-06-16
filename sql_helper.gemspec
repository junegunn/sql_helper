# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sql_helper/version'

Gem::Specification.new do |spec|
  spec.name          = "sql_helper"
  spec.version       = SQLHelper::VERSION
  spec.authors       = ["Junegunn Choi"]
  spec.email         = ["junegunn.c@gmail.com"]
  spec.description   = %q{A simplistic SQL generator}
  spec.summary       = %q{A simplistic SQL generator}
  spec.homepage      = "https://github.com/junegunn/sql_helper"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest"
end
