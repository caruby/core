# This file is the entry point included by applications which reference a CaTissue object or service.

# the caRuby core gem
require 'rubygems'
begin
  gem 'caruby-core'
rescue LoadError
  # The gem is not available; try a local development source.
  $:.unshift 'lib'
end

require 'caruby'
require 'clinical_trials/resource'
require 'clinical_trials/database'
