require 'jinx/helpers/validation'

module ClinicalTrials
  # Import the Java class into Ruby.
  # Extends the Study domain class.
  class Study
    set_secondary_key_attributes(:name)
    
    add_attribute_aliases(:events => :study_events)
    
    add_attribute_defaults(:activity_status => 'Active')

    # The Study events are dependent, but are not cascaded or fetched.
    add_dependent_attribute(:study_events, :logical)
    
    # The Study consents are uni-directional dependents, i.e. they are cascaded and
    # fetched from Study but there is no Consent reference back to its owner Study.
    add_dependent_attribute(:consents)

    private
    
    # @raise [ValidationError] if there are no events
    def validate_local
      super
      raise Jinx::ValidationError.new("Study #{name} is missing study events") if events.nil_or_empty?
    end
  end
end