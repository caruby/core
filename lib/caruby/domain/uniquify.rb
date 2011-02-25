require 'singleton'
require 'caruby/util/uniquifier'
require 'caruby/util/collection'

module CaRuby
  module Resource
    # The Unique mix-in makes values unique within the scope of a Resource class.
    module Unique
      # Makes the given String value unique in the context of this object's class.
      # @return nil if value is nil
      # Raises TypeError if value is neither nil nor a String.
      def uniquify_value(value)
        unless String === value or value.nil? then
          raise TypeError.new("Cannot uniquify #{qp} non-String value #{value}")
        end
        ResourceUniquifier.instance.uniquify(self, value)
      end
      
      # Makes the secondary key unique by replacing each String key attribute value
      # with a unique value.
      def uniquify
        self.class.secondary_key_attributes.each do |attr|
          oldval = send(attr)
          next unless String === oldval
          newval = uniquify_value(oldval)
          set_attribute(attr, newval)
          logger.debug { "Reset #{qp} #{attr} from #{oldval} to unique value #{newval}." }
        end
      end
    end
  end
  
  # The ResourceUniquifier singleton makes Resource instance attribute values unique.
  class ResourceUniquifier
    include Singleton

    def initialize
      @cache = LazyHash.new { Hash.new }
    end

    # Makes the obj attribute value unique, or returns nil if value is nil.
    def uniquify(obj, value)
      @cache[obj.class][value] ||= value.uniquify if value
    end

    def clear
      @cache.clear
    end
  end
end