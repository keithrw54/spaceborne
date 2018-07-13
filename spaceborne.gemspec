# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'spaceborne/version'

Gem::Specification.new do |spec|
  spec.name          = "spaceborne"
  spec.version       = Spaceborne::VERSION
  spec.authors       = ["Keith Williams"]
  spec.email         = ["keithrw@comcast.net"]

  spec.summary       = 'Gem supporting API testing'
  spec.description   = 'Extends brooklynDev/airborne'
  spec.homepage      = "https://github.com/keithrw54/spaceborne.git"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency 'rspec', '~> 3.1'
  spec.add_runtime_dependency 'rest-client', '< 3.0', '>= 1.7.3'
  spec.add_runtime_dependency 'rack-test', '~> 0.6', '>= 0.6.2'
  spec.add_runtime_dependency 'rack'
  spec.add_runtime_dependency 'activesupport'
  spec.add_runtime_dependency "airborne", "~> 0.2.13"
  spec.add_runtime_dependency "curlyrest", "~> 0.1.0"
  spec.add_development_dependency 'webmock', '~> 0'

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "byebug", "~> 2.0"
end
