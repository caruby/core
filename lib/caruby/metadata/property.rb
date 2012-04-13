require 'jinx/metadata/property'
require 'caruby/metadata/property_characteristics'

# Mix persistence into +Jinx::Property+.
module Jinx
  class Property
    include CaRuby::PropertyCharacteristics
  end
end

