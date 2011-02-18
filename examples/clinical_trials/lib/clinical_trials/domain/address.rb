module ClinicalTrials
  # import the Java class into Ruby
  java_import('clinicaltrials.domain.Address')
  
  class Address
    include Resource

    def zip_code=(value)
      value = value.to_s if Integer === value
      setZipCode(value)
    end
    
    add_attribute_aliases(:province => :state, :district => :state, :postal_code => :zip_code)

    add_attribute_defaults(:country => 'US')
  end
end