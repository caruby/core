require File.expand_path('version', File.dirname(__FILE__) + '/lib/caruby')
require 'date'

Gem::Specification.new do |s|
  s.name          = 'caruby-core'
  s.summary       = 'Ruby facade for caBIG applications.'
  s.description   = s.summary
  s.version       = CaRuby::VERSION
  s.date          = Date.today
  s.author        = 'OHSU'
  s.email         = 'caruby.org@gmail.com'
  s.homepage      = 'http://caruby.rubyforge.org''
  s.platform      = Gem::Platform::RUBY
  s.files         = Dir.glob("{conf,lib,test/{bin,lib}}/**/*") + ['History.md', 'LEGAL', 'LICENSE', 'README.md']
  s.require_path  = 'lib'
  s.test_files    = Dir['test/lib/**/*test.rb']
  s.add_dependency 'rack'
  s.add_dependency 'dbi'
  s.add_dependency 'dbd-jdbc'
  s.add_dependency 'fastercsv'
  s.add_dependency 'json_pure'
  s.add_dependency 'uom'
  s.add_dependency 'dbi'
  s.add_development_dependency 'bundler'
  s.add_development_dependency 'yard'
  s.add_development_dependency 'rake'
  s.has_rdoc      = 'yard'
  s.license       = 'MIT'
  s.rubyforge_project = 'caruby'
end