require 'caruby/util/validation'

module CaRuby
  module Domain
    # Metadata mix-in to capture Resource dependency.
    module Dependency
  
      attr_reader :owners, :owner_attributes
  
      # Returns the most specific attribute which references the dependent type, or nil if none.
      # If the given class can be returned by more than dependent attribute, then the attribute
      # is chosen whose return type most closely matches the given class.
      #
      # @param [Class] klass the dependent type
      # @return [Symbol, nil] the dependent reference attribute, or nil if none
      def dependent_attribute(klass)
        dependent_attributes.inject(nil) do |best, attr|
          type = domain_type(attr)
          # If the attribute can return the klass then the return type is a candidate.
          # In that case, the klass replaces the best candidate if it is more specific than
          # the best candidate so far.
          klass <= type ? (best && best < type ? best : type) : best
        end
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
      # @param [<Symbol>] flags the attribute qualifier flags
      def add_dependent_attribute(attribute, *flags)
        attr_md = attribute_metadata(attribute)
        flags << :dependent unless flags.include?(:dependent)
        attr_md.qualify(*flags)
        inverse = attr_md.inverse
        inv_type = attr_md.type
        # example: Parent.add_dependent_attribute(:children) with inverse :parent calls the following:
        #   Child.add_owner(Parent, :children, :parent)
        inv_type.add_owner(self, attribute, inverse)
      end
      
      # Makes a new owner attribute. The attribute name is the lower-case demodulized
      # owner class name. The owner class must reference this class via the given
      # inverse dependent attribute.
      #
      # @param klass (see #detect_owner_attribute)
      # @param [Symbol] the owner -> dependent inverse attribute 
      # @return [Symbol] this class's new owner attribute
      # @raise [ArgumentError] if the inverse is nil
      def create_owner_attribute(klass, inverse)
        if inverse.nil? then
          raise ArgumentError.new("Cannot create a #{qp} owner attribute to #{klass} without a dependent attribute to this class.")
        end
        attr = klass.name.demodulize.underscore.to_sym
        attr_accessor(attr)
        attr_md = add_attribute(attr, klass)
        attr_md.inverse = inverse
        logger.debug { "Created #{qp} owner attribute #{attr} with inverse #{klass.qp}.#{inverse}." }
        attr
      end
      
      # @return [Boolean] whether this class depends on an owner
      def dependent?
        not owners.empty?
      end
      
      # @return [Boolean] whether this class has an owner which cascades save operations to this dependent
      def cascaded_dependent?
        owner_attribute_metadata_enumerator.any? { |attr_md| attr_md.inverse_metadata.cascaded? }
      end
  
      # @return [Boolean] whether this class depends the given other class
      def depends_on?(other)
        owners.detect { |owner| owner === other }
      end
  
      # @param [Class] klass the dependent type
      # @return [Symbol, nil] the attribute which references the dependent type, or nil if none
      def dependent_attribute(klass)
        type = dependent_attributes.detect_with_metadata { |attr_md| attr_md.type == klass }
        return type if type
        dependent_attribute(klass.superclass) if klass.superclass < Resource
      end
  
      # @return [<Symbol>] this class's owner attributes
      def owner_attributes
        @oattrs ||= owner_attribute_metadata_enumerator.transform { |attr_md| attr_md.to_sym }
      end
  
      # @return [<Class>] this class's dependent types
      def dependents
        dependent_attributes.wrap { |attr| attr.type }
      end
  
      # @return [<Class>] this class's owner types
      def owners
        @owners ||= Enumerable::Enumerator.new(owner_attribute_metadata_hash, :each_key)
      end
  
      # @return [Attribute, nil] the sole owner attribute metadata of this class, or nil if there
      #   is not exactly one owner
      def owner_attribute_metadata
        attr_mds = owner_attribute_metadata_enumerator
        attr_mds.first if attr_mds.size == 1
      end
  
      # @return [Symbol, nil] the sole owner attribute of this class, or nil if there
      #   is not exactly one owner
      def owner_attribute
        attr_md = owner_attribute_metadata || return
        attr_md.to_sym
      end
      
      # @return [Class, nil] the sole owner type of this class, or nil if there
      #   is not exactly one owner
      def owner_type
        attr_md = owner_attribute_metadata || return
        attr_md.type
      end
  
      protected
  
      # Adds the given owner class to this dependent class.
      # This method must be called before any dependent attribute is accessed.
      # If the attribute is given, then the attribute inverse is set.
      # Otherwise, if there is not already an owner attribute, then a new owner attribute is created.
      # The name of the new attribute is the lower-case demodulized owner class name.
      #
      # @param [Class] the owner class
      # @param [Symbol] inverse the owner -> dependent attribute
      # @param [Symbol, nil] attribute the dependent -> owner attribute, if known
      # @raise [ValidationError] if the inverse is nil
      def add_owner(klass, inverse, attribute=nil)
        if inverse.nil? then raise ValidationError.new("Owner #{klass.qp} missing dependent attribute for dependent #{qp}") end
        logger.debug { "Adding #{qp} owner #{klass.qp}#{' attribute ' + attribute.to_s if attribute}#{' inverse ' + inverse.to_s if inverse}..." }
        if @owner_attr_hash then
          raise MetadataError.new("Can't add #{qp} owner #{klass.qp} after dependencies have been accessed")
        end
        
        # detect the owner attribute, if necessary
        attribute ||= detect_owner_attribute(klass, inverse)
        attr_md = attribute_metadata(attribute) if attribute
        # Add the owner class => attribute entry.
        # The attribute is nil if the dependency is unidirectional, i.e. there is an owner class which
        # references this class via a dependency attribute but there is no inverse owner attribute.
        local_owner_attribute_metadata_hash[klass] = attr_md
        # If the dependency is unidirectional, then our job is done.
        return if attribute.nil?
  
        # set the inverse if necessary
        unless attr_md.inverse then
          set_attribute_inverse(attribute, inverse)
        end
        # set the owner flag if necessary
        unless attr_md.owner? then attr_md.qualify(:owner) end
        # Redefine the writer method to warn when changing the owner
        rdr, wtr = attr_md.accessors
        logger.debug { "Injecting owner change warning into #{qp}.#{attribute} writer method #{wtr}..." }
        redefine_method(wtr) do |old_wtr|
          lambda do |ref|
            prev = send(rdr)
            if prev and prev != ref then
              if ref.nil? then
                logger.warn("Unsetting the #{self} owner #{attribute} #{prev}.")
              elsif ref.identifier != prev.identifier then
                logger.warn("Resetting the #{self} owner #{attribute} from #{prev} to #{ref}.")
              end
            end
            send(old_wtr, ref)
          end
        end
      end
      
      # Adds the given attribute as an owner. This method is called when a new attribute is added that
      # references an existing owner.
      #
      # @param [Symbol] attribute the owner attribute
      def add_owner_attribute(attribute)
        attr_md = attribute_metadata(attribute)
        otype = attr_md.type
        hash = local_owner_attribute_metadata_hash
        if hash.include?(otype) then
          oattr = hash[otype]
          unless oattr.nil? then
            raise MetadataError.new("Cannot set #{qp} owner attribute to #{attribute} since it is already set to #{oattr}")
          end
          hash[otype] = attr_md
        else
          add_owner(otype, attr_md.inverse, attribute)
        end
      end
  
      # @return [{Class => Attribute}] this class's owner type => attribute hash
      def owner_attribute_metadata_hash
        @oa_hash ||= create_owner_attribute_metadata_hash
      end
      
      private
      
      def local_owner_attribute_metadata_hash
        @local_oa_hash ||= {}
      end
  
      # @return [{Class => Attribute}] a new owner type => attribute hash
      def create_owner_attribute_metadata_hash
        local = local_owner_attribute_metadata_hash
        superclass < Resource ? local.union(superclass.owner_attribute_metadata_hash) : local
      end
      
      # @return [<Attribute>] the owner attributes
      def owner_attribute_metadata_enumerator
        # Enumerate each owner Attribute, filtering out nil values.
        @oa_enum ||= Enumerable::Enumerator.new(owner_attribute_metadata_hash, :each_value).filter
      end
      
      # Returns the attribute which references the owner. The owner attribute is the inverse
      # of the given owner class inverse attribute, if it exists. Otherwise, the owner
      # attribute is inferred by #{Inverse#detect_inverse_attribute}.
  
      # @param klass (see #add_owner)
      # @param [Symbol] inverse the owner -> dependent attribute
      # @return [Symbol, nil] this class's owner attribute
      def detect_owner_attribute(klass, inverse)
        klass.attribute_metadata(inverse).inverse or detect_inverse_attribute(klass)
      end
    end
  end
end