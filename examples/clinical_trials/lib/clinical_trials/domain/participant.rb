require 'caruby/util/validation'

module ClinicalTrials
  # import the Java class into Ruby
  java_import('clinicaltrials.domain.Participant')

  # Extends the Participant domain class.
  class Participant
    include Resource
    
    add_mandatory_attributes(:name, :address)
    
    add_dependent_attribute(:address)
  end
end