require 'rubygems'
require 'bundler/setup'
Bundler.require(:test, :development)
require 'jinx/helpers/log'

# Open the logger.
Jinx::Log.instance.open(File.dirname(__FILE__) + '/../test/results/log/caruby.log', :debug => true)

Dir.glob(File.dirname(__FILE__) + '/support/**/*.rb').each { |f| require f }
