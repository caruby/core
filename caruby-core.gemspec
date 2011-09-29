require 'caruby/version'
require 'date'

CaRuby::SPEC = Gem::Specification.new do |s|
  s.name          = "caruby-core"
  s.summary       = "Ruby facade for caBIG applications." 
  s.description   = <<-eof
    caRuby is a JRuby facade for interaction with caBIG applications.
  eof
  s.version       = CaRuby::VERSION
  s.date          = Date.today
  s.author        = "OHSU"
  s.email         = "caruby.org@gmail.com"
  s.homepage      = "http://caruby.rubyforge.org"
  s.platform      = Gem::Platform::RUBY
  s.files         = Dir.glob("{conf,lib,test/{bin,lib}}/**/*") + ['History.md', 'LEGAL', 'LICENSE', 'README.md']
  s.require_paths = ['lib']
  %w(dbi dbd-jdbc fastercsv json_pure uom).each { |lib| s.add_dependency lib }
  if s.respond_to?(:add_development_dependency) then
    %w(bundler yard rake).each { |lib| s.add_development_dependency lib }
  end
  s.has_rdoc      = 'yard'
  s.license       = 'MIT'
  s.rubyforge_project = 'caruby'
end