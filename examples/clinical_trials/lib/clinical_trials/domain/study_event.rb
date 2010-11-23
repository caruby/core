require 'caruby/util/validation'

module ClinicalTrials
  # import the Java class into Ruby
  java_import('clinicaltrials.domain.StudyEvent')

  # Extends the StudyEvent domain class.
  class StudyEvent
    include Resource
    
    set_secondary_key_attributes(:study, :calendar_event_point)
    
    add_attribute_defaults(:calendar_event_point => 1.0)
  end
end