require 'caruby/domain'

# Example CaRuby::Domain containing some simple domain classes.
module ClinicalTrials
  # @param [Module] mod the resource mix-in module to extend with metadata capability
  def self.extend_module(mod)
    CaRuby::Domain.extend_module(self, :mixin => mod, :package => PKG, :directory => SRC_DIR)
  end

  private

  # Add the Java jar file to the Java path.
  # For a real application, the jar directories path is set in the application properties file,
  # e.g. ~/.clinicaltrials, which is loaded on demand by {Domain#properties}.
  require File.dirname(__FILE__) + '/../../ext/bin/clinicaltrials.jar'

  # The required Java package name.
  PKG = 'clinicaltrials.domain'
  
  # The domain class definitions.
  SRC_DIR = File.dirname(__FILE__) + '/domain'
end

