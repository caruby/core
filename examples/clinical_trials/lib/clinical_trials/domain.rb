require 'caruby/domain'
require 'clinical_trials/resource'
require 'clinical_trials/database'

# Example CaRuby::Domain containing some simple domain classes.
module ClinicalTrials

  private

  # Add the Java jar file to the Java path.
  # For a real application, the jar directories path is set in the application properties file,
  # e.g. ~/.clinicaltrials, which is loaded on demand by {Domain#access_properties}.
  require File.join(File.dirname(__FILE__), '..', '..', 'ext', 'bin', 'clinicaltrials.jar')

  # Load the domain class definitions.

  # The required Java package name.
  PKG = 'clinicaltrials.domain'
  
  # The domain class definitions.
  SRC_DIR = File.join(File.dirname(__FILE__), 'domain')

  # Enable the resource metadata aspect.
  CaRuby::Domain.extend_module(self, :mixin => Resource, :package => PKG)
  
  # Load the class definitions.
  load_dir(SRC_DIR)
end

