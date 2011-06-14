require 'caruby/util/inflector'
require 'caruby/domain/attribute'

module CaRuby
  module Domain
    # The attribute metadata for an introspected Java property. 
    class JavaAttribute < Attribute
  
      # This attribute's Java property descriptor.
      attr_reader :property_descriptor
  
      # This attribute's Java property [reader, writer] accessors, e.g. +[:getActivityStatus, :setActivityStatus]+.
      attr_reader :property_accessors
  
      # Creates a Ruby Attribute symbol corresponding to the given Ruby Java class wrapper klazz
      # and Java property_descriptor.
      #
      # The attribute name is the lower-case, underscore property descriptor name with the alterations
      # described in {JavaAttribute.to_attribute_symbol} and {Class#unocclude_reserved_method}.
      #
      # The attribute type is inferred as follows:
      # * If the property descriptor return type is a primitive Java type, then that type is returned.
      # * If the return type is a parameterized collection, then the parameter type is returned.
      # * If the return type is an unparameterized collection, then this method infers the type from
      #   the property name, e.g. +StudyProtocolCollection+type is inferred as +StudyProtocol+
      #   by stripping the +Collection+ suffix, capitalizing the prefix and looking for a class of
      #   that name in the {Metadata#domain_module}.
      # * If the declarer class metadata configuration includes a +domain_attributes+ property, then
      #   the type specified in that property is returned.
      # * Otherwise, this method returns Java::Javalang::Object.
      #
      # The optional restricted_type argument restricts the attribute to a subclass of the declared
      # property type.
      def initialize(pd, declarer, restricted_type=nil)
        symbol = create_standard_attribute_symbol(pd, declarer)
        super(symbol, declarer, restricted_type)
        @property_descriptor = pd
        # deficient Java introspector does not recognize 'is' prefix for a Boolean property
        rm = declarer.property_read_method(pd)
        raise ArgumentError.new("Property does not have a read method: #{declarer.qp}.#{pd.name}") unless rm
        reader = rm.name.to_sym
        unless declarer.method_defined?(reader) then
          reader = "is#{reader.to_s.capitalize_first}".to_sym
          unless declarer.method_defined?(reader) then
            raise ArgumentError.new("Reader method not found for #{declarer} property #{pd.name}")
          end
        end
        unless pd.write_method then
          raise ArgumentError.new("Property does not have a write method: #{declarer.qp}.#{pd.name}")
        end
        writer = pd.write_method.name.to_sym
        unless declarer.method_defined?(writer) then
          raise ArgumentError.new("Writer method not found for #{declarer} property #{pd.name}")
        end
        @property_accessors = [reader, writer]
        qualify(:collection) if collection_java_class?
        @type = infer_type
      end
      
      # @return [Symbol] the JRuby wrapper method for the Java property reader
      def property_reader
        property_accessors.first
      end
      
      # @return [Symbol] the JRuby wrapper method for the Java property writer
      def property_writer
        property_accessors.last
      end
  
      # Returns a lower-case, underscore symbol for the given property_name.
      # A name ending in 'Collection' is changed to a pluralization.
      #
      # @example
      #   JavaAttribute.to_attribute_symbol('specimenEventCollection') #=> :specimen_events
      def self.to_attribute_symbol(property_name)
        name = if property_name =~ /(.+)Collection$/ then
          property_name[0...-'Collection'.length].pluralize.underscore
        else
          property_name.underscore
        end
        name.to_sym
      end
  
      private
  
      # @param pd the Java property descriptor
      # @param [Class] klass the declarer
      # @return [String] the lower-case, underscore symbol for the given property descriptor
      def create_standard_attribute_symbol(pd, klass)
        propname = pd.name
        name = propname.underscore
        renamed = klass.unocclude_reserved_method(pd)
        if renamed then
          logger.debug { "Renamed #{klass.qp} reserved Ruby method #{name} to #{renamed}." }
          renamed
        else
          JavaAttribute.to_attribute_symbol(propname)
        end
      end
  
      # @return [Boolean] whether this property's Java type is +Iterable+
      def collection_java_class?
        # the Java property type
        ptype = @property_descriptor.property_type
        # Test whether the corresponding JRuby wrapper class or module is an Iterable.
        Class.to_ruby(ptype) < Java::JavaLang::Iterable
      end
  
      # @return [Class] the type for the specified klass property descriptor pd as described in {#initialize}
      def infer_type
        collection? ? infer_collection_type : infer_non_collection_type
      end
  
      # Returns the domain type for this attribute's Java Collection property descriptor.
      # If the property type is parameterized by a single domain class, then that generic type argument is the domain type.
      # Otherwise, the type is inferred from the property name as described in {#infer_collection_type_from_name}.
      #
      # @return [Class] this property's Ruby type
      def infer_collection_type
         generic_parameter_type or infer_collection_type_from_name or Java::JavaLang::Object
      end
  
      # @return [Class] this property's Ruby type
      def infer_non_collection_type
        jtype = @property_descriptor.property_type
        Class.to_ruby(jtype)
      end
  
      # @return [Class, nil] the domain type of this attribute's property descriptor Collection generic
      #   type argument, or nil if none
      def generic_parameter_type
        method = @property_descriptor.readMethod || return
        gtype = method.genericReturnType
        return unless Java::JavaLangReflect::ParameterizedType === gtype
        atypes = gtype.actualTypeArguments
        return unless atypes.size == 1
        atype = atypes[0]
        klass = java_to_ruby_class(atype)
        logger.debug { "Inferred #{declarer.qp} #{self} domain type #{klass.qp} from generic parameter #{atype.name}." } if klass
        klass
      end
  
      # @param [Class, String] jtype the Java class or class name
      # @return [Class] the corresponding Ruby type 
      def java_to_ruby_class(jtype)
        name = String === jtype ? jtype : jtype.name
        Class.to_ruby(name)
      end
  
      # Returns the domain type for this attribute's collection Java property descriptor name.
      # By convention, caBIG domain collection properties often begin with a domain type
      # name and end in 'Collection'. This method strips the Collection suffix and checks
      # whether the prefix is a domain class.
      #
      # For example, the type of the property named +distributionProtocolCollection+
      # is inferred as +DistributionProtocol+ by stripping the +Collection+ suffix,
      # capitalizing the prefix and looking for a class of that name in this classifier's
      # domain_module.
      #
      # @return [Class] the collection item type
      def infer_collection_type_from_name
        # the property name
        pname = @property_descriptor.name
        # The potential class name is the capitalized property name without a 'Collection' suffix.
        cname = pname.capitalize_first.sub(/Collection$/, '')
        jname = [@declarer.parent_module, cname].join('::')
        klass = eval jname rescue nil
        if klass then logger.debug { "Inferred #{declarer.qp} #{self} collection domain type #{klass.qp} from the attribute name." } end
        klass
      end
    end
  end
end