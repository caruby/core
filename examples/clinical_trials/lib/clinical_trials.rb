# This file is the entry point included by applications which reference a CaTissue object or service.

# the caRuby core gem
require 'rubygems'
begin
  gem 'caruby-core'
rescue LoadError
  # if the gem is not available, then try a local development source
  $:.unshift '../caruby/lib/caruby'
end

require 'caruby'
require 'clinical_trials/resource'
