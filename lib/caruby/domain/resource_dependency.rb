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
    # @param [Symbol] inverse the owner attribute defined in the dependent
    # @param [<Symbol>] the attribute qualifier flags
    def add_dependent_attribute(attribute, *flags)
      attr_md = attribute_metadata(attribute)
      unless attr_md.inverse_attribute_metadata.collection? then
        delegate_writer_to_dependent(attribute)
      end
      flags << :dependent unless flags.include?(:dependent)
      attr_md.qualify(*flags)
      inverse = attr_md.inverse
      inv_type = attr_md.type
      # example: Parent.add_dependent_attribute(:children) with inverse :parent calls
      # Child.add_owner(Parent, :parent, :children)
      inv_type.add_owner(self, inverse, attribute)
    end

    # Returns whether this metadata's subject class depends on an owner.
    def dependent?
      not owners.empty?
    end

    # Returns whether this metadata's subject class depends the given other class.
    def depends_on?(other)
      owners.detect { |owner| owner === other }
    end

    # Returns the attribute which references the dependent type, or nil if none.
    def dependent_attribute(dep_type)
      type = dependent_attributes.detect { |attr| domain_type(attr) == dep_type }
      return type if type
      dependent_attribute(dep_type.superclass) if dep_type.superclass < Resource
    end

    # Returns the sole owner attribute of this class, or nil if there is not exactly one owner.
    def owner_attribute
      if @local_owner_attr_hash then
        @local_owner_attr_hash.each_value { |attr| return attr } if @local_owner_attr_hash.size == 1
      elsif superclass < Resource
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

    # If attribute is nil, then the owner attribute is inferred as follows:
    # * If there is exactly one reference attribute from this dependent to the owner klass, then that
    #   attribute is the owner attribute.
    # * Otherwise, if this dependent class has a default attribute name given by the demodulized,
    #   underscored owner class name and that attribute references the owner klass, then that attribute
    #   is the owner attribute.
    # * Otherwise, there is no owner attribute.
    def add_owner(klass, attribute=nil, inverse=nil)
      logger.debug { "Adding #{qp} owner #{klass.qp}..." }
      if @owner_attr_hash then
        raise MetadataError.new("Can't add #{qp} owner #{klass.qp} after dependencies have been accessed")
      end
      @local_owner_attr_hash ||= {}
      @local_owner_attr_hash[klass] = attribute ||= detect_owner_attribute(klass, inverse)

      # augment the owner writer method
      if attribute then
        raise ValidationError.new("Owner #{klass.qp} missing dependent attribute for dependent #{qp}") if inverse.nil?
        set_attribute_inverse(attribute, inverse)
        attribute_metadata(attribute).qualify(:owner)
      else
        logger.debug { "No #{qp} owner attribute detected for #{klass.qp}." }
      end
    end

    # Returns this Resource class's owner type => attribute hash.
    def owner_attribute_hash
      @local_owner_attr_hash or (superclass.owner_attribute_hash if superclass < Resource) or Hash::EMPTY_HASH
    end

    private

    def domain_class?(klass)
      Class === klass and klass.include?(CaRuby::Resource)
    end

    # Redefines the attribute writer method to delegate to its inverse writer.
    #
    # For an attribute +dep+ with setter +setDep+ and inverse +owner+ with setter +setOwner+,
    # this is equivalent to the following:
    #   class Owner
    #     def dep=(d)
    #       d.setOwner(self) if d
    #       setDep(self)
    #     end
    #   end
    def delegate_writer_to_dependent(attribute)
      attr_md = attribute_metadata(attribute)
      # nothing to do if no inverse
      inv_attr_md = attr_md.inverse_attribute_metadata || return
      logger.debug { "Delegating #{qp}.#{attribute} update to the inverse #{attr_md.type}.#{inv_attr_md}..." }
      # redefine the write to set the dependent inverse
      redefine_method(attr_md.writer) do |old_writer|
        # delegate to the CaRuby::Resource set_exclusive_dependent method
        lambda { |dep| set_exclusive_dependent(dep, old_writer, inv_attr_md.writer) }
      end
    end

    # Returns the owner attribute for the given owner klass and inverse, or nil if no
    # owner attribute was detected.
    def detect_owner_attribute(klass, inverse=nil)
      # example: Parent.add_dependent_attribute(:children) without inverse calls
      # Child.add_owner(Parent, nil, :children) which calls
      # Child.detect_owner_attribute(klass, :children)

      # the candidate attributes which return the owner type
      candidates = domain_attributes.map do |attr|
        attr_md = attribute_metadata(attr)
        # possible hit if there is a match on the type
        attr_md if klass.equal?(attr_md.type) or klass <= attr_md.type
      end
      candidates.compact!
      return if candidates.empty?

      # there can be at most one owner attribute per owner.
      return candidates.first.to_sym if candidates.size == 1

      # we have a hit if there is a match on the inverse. in the above example,
      # attribute :parent with inverse :children => :parent is the owner attribute
      candidates.each { |attr_md| return attr_md.to_sym if attr_md.inverse == inverse }

      # by convention, if more than one attribute references the owner type,
      # then the attribute named after the owner type is the owner attribute
      hit = klass.name[/\w+$/].downcase.to_sym
      hit if candidates.detect { |attr_md| attr_md.to_sym == hit }
    end

    # Infers annotation dependent attributes based on whether a domain attribute satisfies the
    # following criteria:
    # 1. the referenced type has an attribute which refers back to this classifier's subject class
    # 2. the referenced type is not an owner of this classifier's subject class
    # Annotation dependencies are not specified in a configuration and follow the above convention.
    def infer_annotation_dependent_attributes
      dep_attrs = []
      domain_attributes.each do |attr|
        next if owner_attribute?(attr)
        ref_md = domain_type(attr).metadata
        owner_attr = ref_md.detect_owner_attribute(subject_class)
        if owner_attr then
          ref_md.add_owner(subject_class, owner_attr)
          dep_attrs << attr
        end
      end
      dep_attrs
    end
  end
end