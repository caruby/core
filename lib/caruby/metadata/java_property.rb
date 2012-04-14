require 'jinx/metadata/java_property'
require 'caruby/metadata/property_characteristics'

# Mix persistence into +Jinx::JavaProperty+.
module CaRuby
  class JavaProperty < Jinx::JavaProperty
    include CaRuby::PropertyCharacteristics
    
    def initialize(pd, declarer, restricted_type=nil)
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
