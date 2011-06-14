require 'caruby/resource'
require 'caruby/domain/id_alias'

module ClinicalTrials
  # The module included by all ClinicalTrials domain classes.
  module Resource
    include CaRuby::Resource, CaRuby::IdAlias
    
    def database
      ClinicalTrials::Database.instance
    end
  end
end

