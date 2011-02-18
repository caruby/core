module ClinicalTrials
  # import the Java class into Ruby
  java_import('clinicaltrials.domain.User')

  # Extends the Study domain class.
  class User
    include Resource

    secondary_key_attributes = [:login]
  end
end