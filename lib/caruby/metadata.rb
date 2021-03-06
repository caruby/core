require 'caruby/metadata/propertied'

module CaRuby
  # The metadata persistence mix-in.
  module Metadata
    include Propertied, Jinx::Metadata
    
    private
    
    # @param [Property] the property to print
    # @return [<Symbol>] the flags to modify the property
    def pretty_print_attribute_flags(prop)
      flags = super
      flags << :logical if prop.logical?
      flags << :autogenerated if prop.autogenerated?
      flags
    end

    # @return [{String => <Symbol>}] the attributes to print
    def pretty_print_attribute_hash
      super.merge!({
        'creatable domain attributes' => creatable_domain_attributes,
        'updatable domain attributes' => updatable_domain_attributes,
        'fetched domain attributes' => fetched_domain_attributes,
        'cascaded domain attributes' => cascaded_attributes
      })
    end
  end
end
