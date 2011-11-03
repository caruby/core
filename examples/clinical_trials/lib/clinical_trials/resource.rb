require 'caruby/resource'
require 'clinical_trials/domain'
require 'clinical_trials/database'
require 'caruby/domain/id_alias'

module ClinicalTrials
  # The module included by all ClinicalTrials domain classes.
  module Resource
    include CaRuby::Resource, CaRuby::IdAlias

    # @return [Database] the mock database for the Clinical Trials example
    def database
      ClinicalTrials::Database.instance
    end

    # Add meta-data capability to this Resource module.
    ClinicalTrials.extend_module(self)
  end
end

