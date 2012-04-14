# This file is the entry point to include for the clinical Trials example.
require 'caruby'
require 'jinx/metadata/id_alias'

# The domain package metadata mix-in. Each domain class automatically
# includes this module when it is referenced.
module ClinicalTrials
  # Add persistence to the domain instances.
  include CaRuby::Resource, Jinx::IdAlias
  
  # Add introspection to this domain module.
  extend Jinx::Importer
  
  # Add persistence to the domain classes.
  @metadata_module = CaRuby::Metadata
  
  # The Java package name.
  packages 'clinicaltrials.domain'
  
  # The JRuby mix-ins are in the domain subdirectory.
  definitions File.expand_path('clinical_trials', File.dirname(__FILE__))
end
