require 'singleton'
require 'caruby/database'

module ClinicalTrials
  # The example mock database.
  class Database < CaRuby::Database
    include Singleton
    
    def initialize
      super(SVC_NAME, ClinicalTrials.access_properties)
    end

    # Returns the CaTissue::Database which stores this object.
    def database
      ClinicalTrials::Database.instance
    end
    
    private
    
    # Dummy application service name
    SVC_NAME = 'clinicaltrials'
  end
end