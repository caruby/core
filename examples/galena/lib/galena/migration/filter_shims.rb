require 'uom'

module CaTissue

  # Declares the classes modified for migration.
  shims Participant, TissueSpecimen, SpecimenCollectionGroup

  class Participant
    # Extracts the Participant first name from the +Initials+ input field.
    def migrate_first_name(value, row)
      self.first_name = value[0, 1]
    end

    # Extracts the Participant last name from the +Initials+ input field.
    def migrate_last_name(value, row)
      self.last_name = value[-1, 1]
    end
  end

  class TissueSpecimen
    # Transforms the +Frozen?+ flag input field to the caTissue specimen type +Frozen Tissue+ value.
    def migrate_specimen_type(value, row)
      'Frozen Tissue' if value =~ /TRUE/i
    end

    # Parses the source field as a UOM::Measurement if it is a string.
    # Otherwises, returns the source value.
    def migrate_initial_quantity(value, row)
      # if value is not a string, then use it as is
      return value unless value.is_a?(String)
      # the value has a unit qualifier; parse the measurement.
      # the unit is normalized to the Specimen standard unit.
      value.to_measurement_quantity(standard_unit)
    end
  end

  class SpecimenCollectionGroup
    # Returns whether this SCG has a SPN.
    def migration_valid?
      surgical_pathology_number
    end
  end
end