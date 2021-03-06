require 'jinx/metadata/property'
require 'caruby/metadata/property_characteristics'

# Mix persistence into +Jinx::Property+.
module CaRuby
  class Property < Jinx::Property
    include CaRuby::PropertyCharacteristics
           
    def initialize(attribute, declarer, type=nil, *flags)
      super
    end
    
    private
    
    # @param [Symbol] the flag to set
    # @return [Boolean] whether the flag is supported
    def flag_supported?(flag)
      super or CaRuby::PropertyCharacteristics::SUPPORTED_FLAGS.include?(flag)
    end
  end
end

