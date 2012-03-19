require File.dirname(__FILE__) + '/lib/caruby/version'
require 'date'

Gem::Specification.new do |s|
  s.name          = 'caruby-core'
  s.summary       = 'Ruby facade for caBIG applications.'
  s.description   = s.summary + '. See caruby.rubyforge.org for more information.'
  s.version       = CaRuby::VERSION
  s.date          = Date.today
  s.author        = 'OHSU'
  s.email         = 'caruby.org@gmail.com'
  s.homepage      = 'http://caruby.rubyforge.org'
  s.files         = Dir.glob("{conf,lib}/**/*") + ['History.md', 'LEGAL', 'LICENSE', 'README.md', 'Gemfile']
  s.require_path  = 'lib'
  s.test_files    = Dir['test/lib/**/*.rb']
  s.add_runtime_dependency     'bundler'
  s.add_runtime_dependency     'rack'
  s.add_runtime_dependency     'rdbi'
  s.add_runtime_dependency     'fastercsv'
  s.add_runtime_dependency     'json_pure'
  s.add_runtime_dependency     'jinx', '~> 2.1.1'
  s.add_runtime_dependency     'jinx-json', '~> 2.1.1'
  s.add_development_dependency 'yard'
  s.add_development_dependency 'rake'
  s.has_rdoc      = 'yard'
  s.license       = 'MIT'
  s.rubyforge_project = 'caruby'
end
