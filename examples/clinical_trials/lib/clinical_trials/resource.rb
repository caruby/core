require 'jinx/resource'
require 'jinx/metadata/id_alias'
require 'clinical_trials/domain'
require 'clinical_trials/database'

module ClinicalTrials
  # The module included by all Clinical Trials domain classes.
  module Resource
    include Jinx::IdAlias, CaRuby::Persistable

    # @return [Database] the mock database for the Clinical Trials example
    def database
      Database.instance
    end
end

