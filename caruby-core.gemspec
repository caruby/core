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
  s.platform      = Gem::Platform::RUBY
  s.files         = Dir.glob("{conf,lib}/**/*") + ['History.md', 'LEGAL', 'LICENSE', 'README.md']
  s.require_path  = 'lib'
  s.test_files    = Dir['test/lib/**/*.rb']
  s.add_dependency 'bundler'
  s.add_dependency 'rack'
  s.add_dependency 'dbi'
  s.add_dependency 'dbd-jdbc'
  s.add_dependency 'fastercsv'
  s.add_dependency 'json_pure'
  s.add_dependency 'dbi'
  s.add_development_dependency 'yard'
  s.add_development_dependency 'rake'
  s.has_rdoc      = 'yard'
  s.license       = 'MIT'
  s.rubyforge_project = 'caruby'
end
