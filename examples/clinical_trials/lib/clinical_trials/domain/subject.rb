module ClinicalTrials
  # Import the Java class into Ruby.
  resource_import Java::clinicaltrials.domain.Subject

  # Extends the Subject domain class.
  class Subject
    set_secondary_key_attributes(:ssn)
    
    add_mandatory_attributes(:ssn, :name)
    
    add_dependent_attribute(:address)
  end
end