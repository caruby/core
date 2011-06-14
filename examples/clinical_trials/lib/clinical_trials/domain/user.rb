module ClinicalTrials
  # Import the Java class into Ruby.
  resource_import Java::clinicaltrials.domain.User

  # Extends the Study domain class.
  class User
    secondary_key_attributes = [:login]
  end
end