$:.unshift File.join(File.dirname(__FILE__), 'lib')

require 'caruby/version'
require 'rbconfig'

# the gem name
GEM = 'caruby-core'
GEM_VERSION = CaRuby::VERSION
GEM_VERSION.replace(ENV['CARUBY_CORE_VERSION']) if ENV['CARUBY_CORE_VERSION']

WINDOWS = (Config::CONFIG['host_os'] =~ /mingw|win32|cygwin/ ? true : false) rescue false
SUDO = WINDOWS ? '' : 'sudo'

# the archive include files
TAR_FILES = Dir.glob("{bin,lib,sql,*.gemspec,doc/website,test/{bin,fixtures,lib}}") +
  ['.gitignore', 'History.txt', 'LEGAL', 'LICENSE', 'Rakefile', 'README.md']

desc "Builds the gem"
task :gem do
  load "#{GEM}.gemspec"
  Gem::Builder.new(SPEC).build
end

desc "Installs the gem"
task :install => :gem do
  sh "#{SUDO} jgem install #{GEM}-#{GEM_VERSION}.gem"
end

desc "Archives the source"
task :tar do
  if WINDOWS then
    sh "zip -r #{GEM}-#{GEM_VERSION}.zip #{TAR_FILES.join(' ')}"
  else
    sh "tar -czf #{GEM}-#{GEM_VERSION}.tar.gz #{TAR_FILES.join(' ')}"
  end
end