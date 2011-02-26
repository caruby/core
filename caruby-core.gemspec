require 'caruby/version'
require 'date'

SPEC = Gem::Specification.new do |s|
  s.name          = "caruby-core"
  s.summary       = "Ruby facade for caBIG applications." 
  s.description   = <<-eof
    caRuby is a JRuby facade for interaction with caBIG applications.
  eof
  s.version       = CaRuby::VERSION
  s.date          = Date.today
  s.author        = "OHSU"
  s.email         = "caruby.org@gmail.com"
  s.homepage      = "http://rubyforge.org/projects/caruby"
  s.platform      = Gem::Platform::RUBY
  s.files         = Dir.glob("{conf,lib,test/{bin,lib}}/**/*") + ['History.txt', 'LEGAL', 'LICENSE', 'README.md']
  s.require_paths = ['lib']
  s.add_dependency('dbi')
  s.add_dependency('fastercsv')
  s.add_dependency('uom')
  s.has_rdoc      = 'yard'
  s.license       = 'MIT'
  s.rubyforge_project = 'caruby'
end