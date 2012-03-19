require 'rubygems'
require 'bundler/setup'
Bundler.require(:test, :development)
require 'jinx/helpers/log'

# Open the logger.
Jinx::Log.instance.open(File.dirname(__FILE__) + '/../results/log/caruby.log', :shift_age => 10, :shift_size => 1048576, :debug => true)
