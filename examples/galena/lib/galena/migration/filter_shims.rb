module ClinicalTrials

  # Declares the classes modified for migration.
  shims Participant

  class Participant
    # Transforms the Participantthe String +SSN+ input field to an integer.
    def migrate_ssn(value, row)
      String === value ? value.split('-').join.to_i : value
    end
  end
end