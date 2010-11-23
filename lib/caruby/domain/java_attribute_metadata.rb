require 'caruby/util/inflector'
require 'caruby/domain/attribute_metadata'

module CaRuby
  # The attribute metadata for an introspected Java property. 
  class JavaAttributeMetadata < AttributeMetadata

    # This attribute's Java property descriptor.
    attr_reader :property_descriptor

    # This attribute's Java property [reader, writer] accessors, e.g. +[:getActivityStatus, :setActivityStatus]+.
    attr_reader :property_accessors

    # Creates a Ruby Attribute symbol corresponding to the given Ruby Java class wrapper klazz
    # and Java property_descriptor.
    #
    # The attribute name is the lower-case, underscore property descriptor name with the alterations
    # described in {JavaAttributeMetadata.to_attribute_symbol} and {Class#unocclude_reserved_method}.
    #
    # The attribute type is inferred as follows:
    # * If the property descriptor return type is a primitive Java type, then that type is returned.
    # * If the return type is a parameterized collection, then the parameter type is returned.
    # * If the return type is an unparameterized collection, then this method infers the type from
    #   the property name, e.g. +StudyProtocolCollection+type is inferred as +StudyProtocol+
    #   by stripping the +Collection+ suffix, capitalizing the prefix and looking for a class of
    #   that name in the {ResourceMetadata#domain_module}.
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
    end
    
    def type
      @type ||= infer_type
    end

    # Returns a lower-case, underscore symbol for the given property_name.
    # A name ending in 'Collection' is changed to a pluralization.
    #
    # @example
    #   JavaAttributeMetadata.to_attribute_symbol('specimenEventCollection') #=> :specimen_events
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
        JavaAttributeMetadata.to_attribute_symbol(propname)
      end
    end

    # Returns whether java_class is an +Iterable+.
    def collection_java_class?
      @property_descriptor.property_type.interfaces.any? { |xfc| xfc.java_object == Java::JavaLang::Iterable.java_class }
    end

    # Returns the type for the specified klass property descriptor pd as described in {#initialize}.
    def infer_type
      collection_java_class? ? infer_collection_type : infer_non_collection_type
    end

    # Returns the domain type for this attribute's Java Collection property descriptor.
    # If the property type is parameterized by a single domain class, then that generic type argument is the domain type.
    # Otherwise, the type is inferred from the property name as described in {#infer_collection_type_from_name}.
    def infer_collection_type
       generic_parameter_type or infer_collection_type_from_name or Java::JavaLang::Object
    end

    def infer_non_collection_type
      prop_type = @property_descriptor.property_type
      if prop_type.primitive then
        Class.to_ruby(prop_type)
      else
        @declarer.domain_module.domain_type_with_name(prop_type.name) or Class.to_ruby(prop_type)
      end
    end

    def configured_type
      name = @declarer.class.configuration.domain_type_name(to_sym) || return
      @declarer.domain_module.domain_type_with_name(name) or java_to_ruby_class(name)
    end

    # Returns the domain type of this attribute's property descriptor Collection generic type argument, or nil if none.
    def generic_parameter_type
      method = @property_descriptor.readMethod || return
      prop_type = method.genericReturnType
      return unless Java::JavaLangReflect::ParameterizedType === prop_type
      arg_types = prop_type.actualTypeArguments
      return unless arg_types.size == 1
      arg_type = arg_types[0]
      klass = java_to_ruby_class(arg_type)
      logger.debug { "Inferred #{declarer.qp} #{self} domain type #{klass.qp} from generic parameter #{arg_type.name}." } if klass
      klass
    end

    def java_to_ruby_class(java_type)
      java_type = java_type.name unless String === java_type
      @declarer.domain_module.domain_type_with_name(java_type) or Class.to_ruby(java_type)
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
    def infer_collection_type_from_name
      prop_name = @property_descriptor.name
      index = prop_name =~ /Collection$/
      index ||= prop_name.length
      prefix = prop_name[0...1].upcase + prop_name[1...index]
      logger.debug { "Inferring #{declarer.qp} #{self} domain type from attribute name prefix #{prefix}..." }
      @declarer.domain_module.domain_type_with_name(prefix)
    end
  end
end