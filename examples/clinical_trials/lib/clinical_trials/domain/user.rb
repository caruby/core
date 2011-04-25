module ClinicalTrials
  resource_import Java::clinicaltrials.domain.User

  # Extends the Study domain class.
  class User
    secondary_key_attributes = [:login]
  end
end