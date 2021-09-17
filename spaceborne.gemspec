lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'spaceborne/version'

Gem::Specification.new do |spec|
  spec.name          = 'spaceborne'
  spec.version       = Spaceborne::VERSION
  spec.authors       = ['Keith Williams']
  spec.email         = ['keithrw@comcast.net']

  spec.summary       = 'Gem supporting API testing'
  spec.description   = 'Extends brooklynDev/airborne'
  spec.homepage      = 'https://github.com/keithrw54/spaceborne.git'
  spec.license       = 'MIT'
  spec.required_ruby_version = '~> 2.6'

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'activesupport'
  spec.add_runtime_dependency 'airborne', '~> 0.3'
  spec.add_runtime_dependency 'curlyrest', '~> 0.1.30'
  spec.add_runtime_dependency 'rack'
  spec.add_runtime_dependency 'rack-test', '~> 1.1', '<= 2.0'
  spec.add_runtime_dependency 'rest-client', '< 3.0', '>= 1.7.3'
  spec.add_runtime_dependency 'rspec', '~> 3.8'
  spec.add_development_dependency 'webmock', '~> 0'

  spec.add_development_dependency 'byebug', '~> 10.0.2'
  spec.add_development_dependency 'rake', '~> 12.3.3'
end
