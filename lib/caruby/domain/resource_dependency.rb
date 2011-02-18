module CaRuby
  # ResourceMetadata mix-in to capture Resource dependency.
  module ResourceDependency

    attr_reader :owners, :owner_attributes

    # Returns the attribute which references the dependent type, or nil if none.
    def dependent_attribute(type)
      dependent_attributes.detect { |attr| type <= domain_type(attr) }
    end

    # Adds the given attribute as a dependent.
    #
    # Supported flags include the following:
    # * :logical - the dependency relation is not cascaded by the application
    # * :autogenerated - a dependent can be created by the application as a side-effect of creating the owner
    # * :disjoint - the dependent owner has more than one owner attribute, but only one owner instance
    #
    # If the attribute inverse is not a collection, then the attribute writer
    # is modified to delegate to the dependent owner writer. This enforces
    # referential integrity by ensuring that the following post-condition holds:
    # *  _owner_._attribute_._inverse_ == _owner_
    # where:
    # * _owner_ is an instance this attribute's declaring class
    # * _inverse_ is the owner inverse attribute defined in the dependent class
    #
    # @param [Symbol] attribute the dependent to add
    # @param [<Symbol>] the attribute qualifier flags
    def add_dependent_attribute(attribute, *flags)
      attr_md = attribute_metadata(attribute)
      flags << :dependent unless flags.include?(:dependent)
      attr_md.qualify(*flags)
      inverse = attr_md.inverse
      inv_type = attr_md.type
      # example: Parent.add_dependent_attribute(:children) with inverse :parent calls
      # Child.add_owner(Parent, :children, :parent)
      inv_type.add_owner(self, attribute, inverse)
    end

    # Returns whether this metadata's subject class depends on an owner.
    def dependent?
      not owners.empty?
    end

    # Returns whether this metadata's subject class depends the given other class.
    def depends_on?(other)
      owners.detect { |owner| owner === other }
    end

    # @return [Symbol, nil] the attribute which references the dependent type,
    #   or nil if none
    def dependent_attribute(dep_type)
      type = dependent_attributes.detect { |attr| domain_type(attr) == dep_type }
      return type if type
      dependent_attribute(dep_type.superclass) if dep_type.superclass < Resource
    end

    # @return [Symbol, nil] the sole owner attribute of this class, or nil if there
    #   is not exactly one owner
    def owner_attribute
      if @local_owner_attr_hash then
        # the sole attribute in the owner class => attribute hash
        @local_owner_attr_hash.each_value { |attr| return attr } if @local_owner_attr_hash.size == 1
      elsif superclass < Resource
        # delegate to superclass
        superclass.owner_attribute
      end
    end

    # Returns this Resource class's owner types.
    def owner_attributes
      if @local_owner_attr_hash then
        @local_owner_attrs ||= Enumerable::Enumerator.new(@local_owner_attr_hash, :each_value).filter
      elsif superclass < Resource
        superclass.owner_attributes
      else
        Array::EMPTY_ARRAY
      end
    end

    # Returns this Resource class's dependent types.
    def dependents
      dependent_attributes.wrap { |attr| attr.type }
    end

    # Returns this Resource class's owner types.
    def owners
      if @local_owner_attr_hash then
        @local_owners ||= Enumerable::Enumerator.new(@local_owner_attr_hash, :each_key)
      elsif superclass < Resource
        superclass.owners
      else
        Array::EMPTY_ARRAY
      end
    end

    protected

    # Adds the given owner class to this dependent class.
    # This method must be called before any dependent attribute is accessed.
    #
    # @param [Class] the owner class
    # @param [Symbol, nil] inverse the owner -> dependent attribute
    # @param [Symbol, nil] attribute the dependent -> owner attribute, if known
    # @raise [ValidationError] if there is no owner -> dependent inverse attribute
    # @raise [MetadataError] if this method is called after a dependent attribute has been accessed
    def add_owner(klass, inverse, attribute=nil)
      logger.debug { "Adding #{qp} owner #{klass.qp}#{' attribute ' + attribute.to_s if attribute}#{' inverse ' + inverse.to_s if inverse}..." }
      if @owner_attr_hash then
        raise MetadataError.new("Can't add #{qp} owner #{klass.qp} after dependencies have been accessed")
      end
      @local_owner_attr_hash ||= {}
      @local_owner_attr_hash[klass] = attribute ||= detect_inverse_attribute(klass)

      # set the inverse
      if attribute then
        if inverse.nil? then raise ValidationError.new("Owner #{klass.qp} missing dependent attribute for dependent #{qp}") end
        set_attribute_inverse(attribute, inverse)
        attribute_metadata(attribute).qualify(:owner)
      else
        logger.debug { "No #{qp} owner attribute detected for #{klass.qp}." }
      end
    end

    # @return [{Class => Symbol}] this Resource class's owner type => attribute hash
    def owner_attribute_hash
      @local_owner_attr_hash or (superclass.owner_attribute_hash if superclass < Resource) or Hash::EMPTY_HASH
    end
  end
end