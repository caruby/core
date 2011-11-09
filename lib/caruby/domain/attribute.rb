require 'set'
require 'caruby/helpers/inflector'
require 'caruby/helpers/collection'
require 'caruby/helpers/validation'
require 'caruby/domain/java_attribute'

module CaRuby
  module Domain
    # An Attribute captures the following metadata about a domain class attribute:
    # * attribute symbol
    # * declarer type
    # * return type
    # * reader method symbol
    # * writer method symbol
    class Attribute
      # The supported attribute qualifier flags. See the complementary methods for an explanation of
      # the flag option, e.g. {#autogenerated?} for the +:autogenerated+ flag.
      SUPPORTED_FLAGS = [
        :autogenerated, :autogenerated_on_update, :collection, :dependent, :derived, :logical, :disjoint,
        :owner, :cascaded, :no_cascade_update_to_create, :saved, :unsaved, :optional, :fetched, :unfetched,
        :include_in_save_template, :saved_fetch, :create_only, :update_only, :unidirectional, :volatile].to_set
  
      # @return [(Symbol, Symbol)] the standard attribute reader and writer methods
      attr_reader :accessors
  
      # @return [Class] the declaring class
      attr_reader :declarer
      
      # @return [Class] the return type
      attr_reader :type
      
      # @return [<Symbol>] the qualifier flags
      # @see SUPPORTED_FLAGS
      attr_accessor :flags
  
      # Creates a new Attribute from the given attribute.
      #
      # The return type is the referenced entity type. An attribute whose return type is a
      # collection of domain objects is thus the domain object class rather than a collection class.
      #
      # @param [String,Symbol] attr the subject attribute
      # @param [Class] declarer the declaring class
      # @param [Class] type the return type
      # @param [<Symbol>] flags the qualifying flags
      # @option flags :dependent the attribute references a dependent
      # @option flags :collection the attribute return type is a collection
      # @option flags :owner the attribute references the owner of a dependent
      # @option flags :cascaded database create/update/delete operation propagates to the attribute reference
      def initialize(attribute, declarer, type=nil, *flags)
        # the attribute symbol
        @symbol = attribute.to_sym
        # the declaring class
        @declarer = declarer
        # the Ruby class
        @type = Class.to_ruby(type) if type
        # the read and write methods
        @accessors = [@symbol, "#{attribute}=".to_sym]
        # the qualifier flags
        @flags = Set.new
        # identifier is always volatile
        if @symbol == :identifier then flags << :volatile end
        qualify(*flags)
      end
  
      # @return [Symbol] the reader method
      def reader
        accessors.first
      end
  
      # @return [Symbol] the writer method
      def writer
        accessors.last
      end
  
      # @return [Symbol, nil] the inverse of this attribute, if any
      def inverse
        @inv_md.to_sym if @inv_md
      end
      
      # An attribute is unidirectional if both of the following is true:
      # * there is no distinct {#inverse} attribute
      # * the attribute is not a {#dependent?} with more than one owner
      #
      # @return [Boolean] whether this attribute does not have an inverse
      def unidirectional?
        inverse.nil? and not (dependent? and type.owner_attributes.size > 1)
      end
      
      # @param [Class] the attribute return type
      def type=(klass)
        return if klass == @type
        @type = klass
        if @inv_md then
          self.inverse = @inv_md.to_sym
          logger.debug { "Reset #{@declarer.qp}.#{self} inverse from #{@inv_md.type}.#{@inv_md} to #{klass}#{@inv_md}." }
        end
      end
      
      # Creates a new declarer attribute which qualifies this attribute for the given declarer.
      #
      # @param declarer (see #restrict)
      # @param [<Symbol>] flags the additional flags for the restricted attribute
      # @return (see #restrict)
      def restrict_flags(declarer, *flags)
        copy = restrict(declarer)
        copy.qualify(*flags)
        copy
      end
  
      # Sets the inverse of the subject attribute to the given attribute.
      # The inverse relation is symmetric, i.e. the inverse of the referenced Attribute
      # is set to this Attribute's subject attribute.
      #
      # @param [Symbol, nil] attribute the inverse attribute
      # @raise [MetadataError] if the the inverse of the inverse is already set to a different attribute
      def inverse=(attribute)
        return if inverse == attribute
        # if no attribute, then the clear the existing inverse, if any
        return clear_inverse if attribute.nil?
        # the inverse attribute meta-data
        begin
          @inv_md = type.attribute_metadata(attribute)
        rescue NameError => e
          CaRuby.fail(MetadataError, "#{@declarer.qp}.#{self} inverse attribute #{type.qp}.#{attribute} not found", e)
        end
        # the inverse of the inverse
        inv_inv_md = @inv_md.inverse_metadata
        # If the inverse of the inverse is already set to a different attribute, then raise an exception.
        if inv_inv_md and not (inv_inv_md == self or inv_inv_md.restriction?(self))
          CaRuby.fail(MetadataError, "Cannot set #{type.qp}.#{attribute} inverse attribute to #{@declarer.qp}.#{self} since it conflicts with existing inverse #{inv_inv_md.declarer.qp}.#{inv_inv_md}")
        end
        # Set the inverse of the inverse to this attribute.
        @inv_md.inverse = @symbol
        # If this attribute is disjoint, then so is the inverse.
        @inv_md.qualify(:disjoint) if disjoint?
        logger.debug { "Assigned #{@declarer.qp}.#{self} attribute inverse to #{type.qp}.#{attribute}." }
     end
  
      # @return [Attribute, nil] the metadata for the {#inverse} attribute, if any
      def inverse_metadata
        @inv_md
      end
  
      # Qualifies this attribute with the given flags. Supported flags are listed in {SUPPORTED_FLAGS}.
      #
      # @param [<Symbol>] the flags to add
      # @raise [ArgumentError] if the flag is not supported
      def qualify(*flags)
        flags.each { |flag| set_flag(flag) }
        # propagate to restrictions
        if @restrictions then @restrictions.each { |attr_md| attr_md.qualify(*flags) } end
      end
  
      # @return whether the subject attribute encapsulates a Java property
      def java_property?
        JavaAttribute === self
      end
  
      # @return whether the subject attribute returns a domain object or collection of domain objects
      def domain?
        # the type must be a Ruby class rather than a Java Class, and include the Domain mix-in
        Class === type and type < Resource
      end
  
      # @return whether the subject attribute is not a domain object attribute
      def nondomain?
        not domain?
      end
  
      # Returns whether the subject attribute is fetched, determined as follows:
      # * An attribute marked with the :fetched flag is fetched.
      # * An attribute marked with the :unfetched flag is not fetched.
      # Otherwise, a non-domain attribute is fetched, and a domain attribute is
      # fetched if one of the following conditions hold:
      # * A dependent domain attribute is fetched if it is not logical.
      # * An owner domain attribute is fetched by default.
      # * An independent domain attribute is fetched if it is abstract and not derived.
      #
      # @return [Boolean] whether the attribute is fetched
      def fetched?
        return true if @flags.include?(:fetched)
        return false if @flags.include?(:unfetched)
        nondomain? or dependent? ? fetched_dependent? : fetched_independent?
      end
  
      # @return whether the subject attribute return type is a collection
      def collection?
        @flags.include?(:collection)
      end
  
      # Returns whether the subject attribute is a dependent on a parent. See the caRuby configuration
      # documentation for a dependency description.
      #
      # @return [Boolean] whether the attribute references a dependent
      def dependent?
        @flags.include?(:dependent)
      end
  
      # Returns whether the subject attribute is marked as optional in a create.
      # This method returns true only if the :optional flag is explicitly set.
      # Other attributes are optional by default.
      #
      # @return [Boolean] whether the attribute is optional
      # @see Attributes#mandatory_attributes.
      def optional?
        @flags.include?(:optional)
      end
  
      # Returns whether the subject attribute is not saved.
      #
      # @return [Boolean] whether the attribute is unsaved
      def unsaved?
        @flags.include?(:unsaved)
      end
  
      # Returns whether the subject attribute is a dependent whose value is automatically generated
      # with place-holder domain objects when the parent is created. An attribute is auto-generated
      # if the +:autogenerate+ or the +:autogenerated_on_update+ flag is set.
      #
      # @return [Boolean] whether the attribute is auto-generated
      def autogenerated?
        @flags.include?(:autogenerated) or @flags.include?(:autogenerated_on_update)
      end
      
      # Returns whether the the subject attribute is {#autogenerated?} for create. An attribute is
      # auto-generated for create if the +:autogenerate+ flag is set and the
      # +:autogenerated_on_update+ flag is not set.
      #
      # @return [Boolean] whether the attribute is auto-generated on create
      def autogenerated_on_create?
        @flags.include?(:autogenerated) and not @flags.include?(:autogenerated_on_update)
      end
      
      # Returns whether this attribute must be fetched when a declarer instance is saved.
      # An attribute is a saved fetch attribute if either of the following conditions hold:
      # * it is {#autogenerated?}
      # * it is {#cascaded?} and marked with the +:unfetched+ flag.
      #
      # @return [Boolean] whether the subject attribute must be refetched in order to reflect
      #   the database content
      def saved_fetch?
         @flags.include?(:saved_fetch) or autogenerated? or (cascaded? and @flags.include?(:unfetched))
      end
  
      # Returns whether the subject attribute is a dependent whose owner does not automatically
      # cascade application service creation or update to the dependent. It is incumbent upon
      # CaRuby::Database to cascade the changes.
      #
      # @return [Boolean] whether the attribute is an uncascaded dependent
      def logical?
        @flags.include?(:logical)
      end
  
      # An attribute is derived if the attribute value is set by setting another attribute, e.g. if this
      # attribute is the inverse of a dependent owner attribute.
      #
      # @return [Boolean] whether this attribute is derived from another attribute
      def derived?
        @flags.include?(:derived) or (dependent? and !!inverse)
      end
  
      # @return [Boolean] this attribute's inverse attribute if the inverse is a derived attribute, or nil otherwise
      def derived_inverse
        @inv_md.to_sym if @inv_md and @inv_md.derived?
      end
  
      # An independent attribute is a reference to one or more non-dependent Resource objects.
      # An {#owner?} attribute is independent.
      #
      # @return [Boolean] whether the subject attribute is a non-dependent domain attribute
      def independent?
        domain? and not dependent?
      end
  
      # A Java attribute is creatable if all of the following conditions hold:
      # * the attribute is {#saved?}
      # * the attribute is not a {#proxied_save?}
      # * the attribute :update_only flag is not set
      #
      # @return [Boolean] whether this attribute is saved in a create operation
      def creatable?
        saved? and not @flags.include?(:update_only)
      end
  
      # A Java attribute is an uncreated dependent if any of the following conditions hold:
      # * the attribute is a {#logical?} dependent
      # * the attribute is a {#dependent?} which is not {#creatable?}
      #
      # @return [Boolean] whether this attribute is saved in a create operation
      def uncreated_dependent?
        logical? or (dependent? and not creatable?)
      end
  
      # A Java attribute is updatable if all of the following conditions hold:
      # * the attribute is {#saved?}
      # * the attribute :create_only flag is not set
      #
      # @return [Boolean] whether this attribute is saved in a update operation
      def updatable?
        saved? and not @flags.include?(:create_only)
      end
  
      # @return [Boolean] whether the attribute is a physical dependent or the +:cascaded+ flag is set
      def cascaded?
        (dependent? and not logical?) or @flags.include?(:cascaded)
      end
      
      # @return whether this attribute is {#cascaded?} or marked with the +:include_in_save_template+ flag
      def include_in_save_template?
        cascaded? or @flags.include?(:include_in_save_template)
      end
      
      # Returns whether this attribute is #{#cascaded?} and cascades a parent update to a child
      # create. This corresponds to the Hibernate +save-update+ cascade style but not the Hibernate
      # +all+ cascade style.
      #
      # This method returns true if this attribute is cascaded and the +:no_cascade_update_to_create+
      # flag is not set. Set this flag if the Hibernate mapping specifies the +all+ cascade style.
      # Failure to set this flag will result in the caTissue Hibernate error:
      #   Exception: gov.nih.nci.system.applicationservice.ApplicationException:
      #   The given object has a null identifier:
      # followed by the attribute type name.
      #
      # @return [Boolean] whether the attribute cascades to crate when the owner is updated
      def cascade_update_to_create?
        cascaded? and not @flags.include?(:no_cascade_update_to_create)
      end
  
      # A Java property attribute is saved if none of the following conditions hold:
      # *  the attribute :unsaved flag is set
      # *  the attribute is {#proxied_save?}
      # and any of the following conditions hold:
      # * the attibute is {#nondomain?}
      # * the attribute is cascaded
      # * the attribute value is not a collection
      # * the attribute does not have an inverse
      # * the attribute :saved flag is set
      #
      # @return [Boolean] whether this attribute is saved in a create or update operation
      def saved?
        @flags.include?(:saved) or
        (java_property? and not @flags.include?(:unsaved) and not proxied_save? and
         (nondomain? or cascaded? or not collection? or inverse.nil? or unidirectional_java_dependent?))
      end
      
      # @return [Boolean] whether this attribute is not {#saved?}
      def unsaved?
        not saved?
      end
      
      # @return [Boolean] whether the attribute return {#type} is a Resource class which
      #   implements the saver_proxy method
      def proxied_save?
        domain? and type.method_defined?(:saver_proxy)
      end
  
      # Returns whether this attribute's referents must exist before an instance of the
      # declarer class can be created. An attribute is a storable prerequisite if it is
      # either:
      # * a {#cascaded?} dependent which does not #{#cascade_update_to_create?}, or
      # * a {#saved?} {#independent?} 1:M or M:N association.
      #
      # @return [Boolean] whether this attribute is a create prerequisite
      def storable_prerequisite?
        return true if cascaded? and @flags.include?(:no_cascade_update_to_create)
        return false unless independent? and saved?
        return true unless collection?
        inv_md = inverse_metadata
        inv_md.nil? or inv_md.collection?
      end
  
      # @return [Boolean] whether this attribute is a collection with a collection inverse
      def many_to_many?
        return false unless collection?
        inv_md = inverse_metadata
        inv_md and inv_md.collection?
      end
  
      # @return [Boolean] whether the subject attribute is not saved
      def transient?
        not saved?
      end
  
      # Returns whether this attribute is set on the server as a side-effect
      # of a change to the declarer object. The volatile attributes include
      # those which are {#unsaved?} and those which are saved but marked
      # with the +:volatile+ flag.
      #
      # @return [Boolean] whether this attribute's value is determined by the server
      def volatile?
        unsaved? or @flags.include?(:volatile)
      end
  
      # @return [Boolean] whether this is a non-collection Java attribute
      def searchable?
        java_property? and not collection?
      end
  
      # @return [Boolean] whether the subject attribute is a dependency owner
      def owner?
        @flags.include?(:owner)
      end
  
      # @return [Boolean] whether this is a dependent attribute which has exactly one owner value chosen from
      # several owner attributes.
      def disjoint?
        @flags.include?(:disjoint)
      end
      
      # @return [Boolean] whether this attribute is a dependent which does not have a Java inverse owner attribute
      def unidirectional_java_dependent?
        dependent? and java_property? and not bidirectional_java_association?
      end
  
      # @return [Boolean] whether this is a Java attribute which has a Java inverse
      def bidirectional_java_association?
        inverse and java_property? and inverse_metadata.java_property?
      end
      
      # Creates a new declarer attribute which restricts this attribute.
      # This method should only be called by a {Resource} class, since the class is responsible
      # for resetting the attribute symbol => meta-data association to point to the new restricted
      # attribute.
      #
      # If this attribute has an inverse, then the restriction inverse is set to the attribute
      # declared by the restriction declarer'. For example, if:
      # * +AbstractProtocol.coordinator+ has inverse +Administrator.protocol+ 
      # * +AbstractProtocol+ has subclass +StudyProtocol+
      # * +StudyProtocol.coordinator+ returns a +StudyCoordinator+
      # * +AbstractProtocol.coordinator+ is restricted to +StudyProtocol+
      # then calling this method on the +StudyProtocol.coordinator+ restriction
      # sets the +StudyProtocol.coordinator+ inverse to +StudyCoordinator.coordinator+.
      #
      # @param [Class] declarer the subclass which declares the new restricted attribute
      # @param [Hash, nil] opts the restriction options
      # @option opts [Class] type the restriction return type (default this attribute's return type)
      # @option opts [Symbol] type the restriction inverse (default this attribute's inverse) 
      # @return [Attribute] the new restricted attribute
      # @raise [ArgumentError] if the restricted declarer is not a subclass of this attribute's declarer
      # @raise [ArgumentError] if there is a restricted return type and it is not a subclass of this
      #   attribute's return type
      # @raise [MetadataError] if this attribute has an inverse that is not independently declared by
      #   the restricted declarer subclass 
      def restrict(declarer, opts={})
        rtype = opts[:type] || @type
        rinv = opts[:inverse] || inverse
        unless declarer < @declarer then
          CaRuby.fail(ArgumentError, "Cannot restrict #{@declarer.qp}.#{self} to an incompatible declarer type #{declarer.qp}")
        end
        unless rtype <= @type then
          CaRuby.fail(ArgumentError, "Cannot restrict #{@declarer.qp}.#{self}({@type.qp}) to an incompatible return type #{rtype.qp}")
        end
        # Copy this attribute and its instance variables minus the restrictions and make a deep copy of the flags.
        rst = deep_copy
        # specialize the copy declarer
        rst.set_restricted_declarer(declarer)
        # Capture the restriction to propagate modifications to this metadata, esp. adding an inverse.
        @restrictions ||= []
        @restrictions << rst
        # Set the restriction type
        rst.type = rtype
        # Specialize the inverse to the restricted type attribute, if necessary.
        rst.inverse = rinv
        rst
      end
       
      def to_sym
        @symbol
      end
  
      def to_s
        @symbol.to_s
      end
  
      alias :inspect :to_s
  
      alias :qp :to_s
      
      protected
      
      # Duplicates the mutable content as part of a {#deep_copy}.
      def dup_content
        # keep the copied flags but don't share them
        @flags = @flags.dup
        # restrictions and inverse are neither shared nor copied
        @inv_md = @restrictions = nil
      end
      
      # @param [Attribute] other the other attribute to check
      # @return [Boolean] whether the other attribute restricts this attribute
      def restriction?(other)
        @restrictions and @restrictions.include?(other)
      end 
      
      # @param [Class] klass the declaring class of this restriction attribute
      def set_restricted_declarer(klass)
        if @declarer and not klass < @declarer then
          CaRuby.fail(MetadataError, "Cannot reset #{declarer.qp}.#{self} declarer to #{type.qp}")
        end
        @declarer = klass
        @declarer.add_restriction(self)
      end
      
      private
      
      # Creates a copy of this metadata which does not share mutable content.
      #
      # The copy instance variables are as follows:
      # * the copy inverse and restrictions are empty
      # * the copy flags is a deep copy of this attribute's flags
      # * other instance variable references are shared between the copy and this attribute
      #
      # @return [Attribute] the copied attribute
      def deep_copy
        other = dup
        other.dup_content
        other
      end
      
      def clear_inverse
        return unless @inv_md
        logger.debug { "Clearing #{@declarer.qp}.#{self} inverse #{type.qp}.#{inverse}..." }
        # Capture the inverse before unsetting it.
        inv_md = @inv_md
        # Unset the inverse.
        @inv_md = nil
        # Clear the inverse of the inverse.
        inv_md.inverse = nil
        logger.debug { "Cleared #{@declarer.qp}.#{self} inverse." }
      end
      
      # @param [Symbol] the flag to set
      # @raise [ArgumentError] if flag is not supported
      def set_flag(flag)
        return if @flags.include?(flag)
        CaRuby.fail(ArgumentError, "Attribute flag not supported: #{flag}") unless SUPPORTED_FLAGS.include?(flag)
        @flags << flag
        case flag
          when :owner then owner_flag_set
          when :dependent then dependent_flag_set
        end
      end
      
      # This method is called when the owner flag is set.
      # The inverse is inferred as the referenced owner type's dependent attribute which references
      # this attribute's type.
      #
      # @raise [MetadataError] if this attribute is dependent or an inverse could not be inferred
      def owner_flag_set
        if dependent? then
          CaRuby.fail(MetadataError, "#{declarer.qp}.#{self} cannot be set as a #{type.qp} owner since it is already defined as a #{type.qp} dependent")
        end
        inv_attr = type.dependent_attribute(@declarer)
        if inv_attr.nil? then
          CaRuby.fail(MetadataError, "#{@declarer.qp} owner attribute #{self} does not have a #{type.qp} dependent inverse")
        end
        logger.debug { "#{declarer.qp}.#{self} inverse is the #{type.qp} dependent attribute #{inv_attr}." }
        self.inverse = inv_attr
        if inverse_metadata.logical? then @flags << :logical end
      end
      
      # Validates that this is not an owner attribute.
      #
      # @raise [MetadataError] if this is an owner attribute
      def dependent_flag_set
        if owner? then
          CaRuby.fail(MetadataError, "#{declarer.qp}.#{self} cannot be set as a  #{type.qp} dependent since it is already defined as a #{type.qp} owner")
        end
      end
  
      # @return [Boolean] whether this dependent attribute is fetched. Only physical dependents are fetched by default.
      def fetched_dependent?
        not (logical? or @flags.include?(:unfetched))
      end
  
      # @return [Boolean] whether this independent attribute is fetched. Only abstract, non-derived independent
      # references are fetched by default.
      def fetched_independent?
        type.abstract? and not (derived? or  @flags.include?(:unfetched))
      end
    end
  end
end