module ClinicalTrials
  # Declares the classes modified for migration.
  shims Subject

  class Subject
    # @param [String] the input SSN field value
    # @return [Integer] the input field as an integer
    def migrate_ssn(value, row)
      String === value ? value.split('-').join.to_i : value
    end
  end
end