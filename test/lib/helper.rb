# Place the unit tests and the example on the load path.
$:.unshift File.dirname(__FILE__),  File.dirname(__FILE__) + '/../../examples/clinical_trials/lib'

require 'rubygems'
require 'bundler/setup'
Bundler.require(:test, :development)

require 'caruby/helpers/log'

# Open the logger.
CaRuby::Log.instance.open(File.dirname(__FILE__) + '/../results/log/caruby.log', :shift_age => 10, :shift_size => 1048576, :debug => true)
