module ClinicalTrials
  # import the Java class into Ruby
  resource_import Java::clinicaltrials.domain.Participant

  # Extends the Participant domain class.
  class Participant
    set_secondary_key_attributes(:ssn)
    
    add_mandatory_attributes(:ssn, :name)
    
    add_dependent_attribute(:address)
  end
end