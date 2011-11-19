require File.expand_path('version', File.dirname(__FILE__) + '/lib/caruby')

# the gem name
GEM = 'caruby-core'
GEM_VERSION = CaRuby::VERSION

WINDOWS = (Config::CONFIG['host_os'] =~ /mingw|win32|cygwin/ ? true : false) rescue false
SUDO = WINDOWS ? '' : 'sudo'

# the archive include files
TAR_FILES = Dir.glob("{bin,lib,sql,*.gemspec,doc/website,test/{bin,fixtures,lib}}") +
  ['.gitignore', 'History.md', 'LEGAL', 'LICENSE', 'Rakefile', 'README.md']

desc "Builds the gem"
task :gem do
  sh "jgem build #{GEM}.gemspec"
end

desc "Installs the gem"
task :install => :gem do
  sh "#{SUDO} jgem install #{GEM}-#{GEM_VERSION}.gem"
end

desc "Runs all tests"
task :test do
  Dir[File.dirname(__FILE__) + '/**/test/**/*_test.rb'].each { |f| system('jruby', f) }
end

desc "Archives the source"
task :tar do
  if WINDOWS then
    sh "zip -r #{GEM}-#{GEM_VERSION}.zip #{TAR_FILES.join(' ')}"
  else
    sh "tar -czf #{GEM}-#{GEM_VERSION}.tar.gz #{TAR_FILES.join(' ')}"
  end
end
