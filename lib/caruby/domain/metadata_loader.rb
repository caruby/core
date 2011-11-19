require 'caruby/domain/metadata'
require 'caruby/resource'

module CaRuby
  module Domain
    # MetadataLoader introspects a domain class.
    # A module which includes this mix-in is required to set the {#introspected},
    # {#mixin} and {#metadata} attributes.
    module MetadataLoader
      # @return [<Class>] the introspected classes
      attr_reader :introspected
    
      # @return [Module] the resource mix-in module included in every introspected class
      attr_reader :mixin
    
      # @return [Module, Proc] the optional application-specific extension module or proc
      attr_reader :metadata
    
      # Introspects the given class meta-data.
      #
      # If the module which extends this loader implements the +metadata_added+ callback
      # method, then that method is called with the introspected class.
      #
      # @param [Class] klass the class to enable
      def add_metadata(klass)
        # Mark the class as introspected. Do this first to preclude a recursive loop back
        # into this method when the references are introspected below.
        introspected << klass
        # The domain module.
        mod = klass.parent_module
        # Add the superclass meta-data if necessary.
        sc = klass.superclass
        unless introspected.include?(sc) or sc.parent_module != mod then
          add_metadata(sc)
        end
        # Include the mixin.
        unless klass < mixin then
          m = mixin
          klass.class_eval { include m }
        end
        # Add the class metadata.
        klass.extend(Metadata)
        case metadata
          when Module then klass.extend(metadata) 
          when Proc then metadata.call(klass)
        end
        # Set the class domain module.
        klass.domain_module = self
        # Add referenced domain class metadata as necessary.
        klass.each_attribute_metadata do |attr_md|
          ref = attr_md.type
          if ref.nil? then CaRuby.fail(MetadataError, "#{self} #{attr_md} domain type is unknown.") end
          unless introspected.include?(ref) or ref.parent_module != mod then
            logger.debug { "Adding #{qp} #{attr_md} reference #{ref.qp} metadata..." }
            add_metadata(ref)
          end
        end
        if respond_to?(:metadata_added) then metadata_added(klass) end
      end
    end
  end
end