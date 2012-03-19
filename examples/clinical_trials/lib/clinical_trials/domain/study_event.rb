module ClinicalTrials
  # Import the Java class into Ruby.
  # Extends the StudyEvent domain class.
  class StudyEvent
    set_secondary_key_attributes(:study, :calendar_event_point)
    
    add_attribute_defaults(:calendar_event_point => 1.0)
  end
end