require 'jinx/metadata/property_characteristics'

module CaRuby
  # The CaRuby::PropertyCharacteristics mixin captures persistence metadata.
  module PropertyCharacteristics
    # The supported persistence-specific property qualifier flags. This set augments the
    # +Jinx::Property::SUPPORTED_FLAGS+ set for persistence adapters. See the complementary
    # methods for an explanation of the flag option, e.g. {#autogenerated?} for the
    # +:autogenerated+ flag.
    SUPPORTED_FLAGS = [
      :autogenerated, :logical, :cascaded, :no_cascade_update_to_create, :saved, :unsaved, :fetched,
      :unfetched, :include_in_save_template, :fetch_saved, :create_only, :update_only, :nosync,
      :volatile].to_set

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

    # Returns whether the subject attribute is not saved.
    #
    # @return [Boolean] whether the attribute is unsaved
    def unsaved?
      @flags.include?(:unsaved)
    end

    # Returns whether the subject attribute is a dependent whose value is automatically generated
    # with place-holder domain objects when the parent is created. An attribute is auto-generated
    # if the +:autogenerated+ flag is set.
    #
    # @return [Boolean] whether the attribute is auto-generated
    def autogenerated?
      @flags.include?(:autogenerated)
    end
    
    # Returns whether this attribute must be fetched when a declarer instance is saved.
    # An attribute is a saved fetch attribute if any of the following conditions hold:
    # * it is {#autogenerated?}
    # * it is {#cascaded?} and marked with the +:unfetched+ flag
    # * it is marked with the +:fetch_saved+ flag
    #
    # @return [Boolean] whether the subject attribute must be refetched in order to reflect
    #   the database content
    def fetch_saved?
       @flags.include?(:fetch_saved) or autogenerated? or (cascaded? and @flags.include?(:unfetched))
    end

    # Returns whether the subject attribute is either:
    # 1. an owner attribute which does not automatically cascade application service creation
    #    or update to the referenced dependent, or
    # 2. the dependent attribute whose inverse is a logical owner attribute
    #
    # @return [Boolean] whether the attribute is an uncascaded dependent
    def logical?
      @flags.include?(:logical) or (owner? and inverse_property and inverse_property.logical?)
    end

    # A Java attribute is creatable if all of the following conditions hold:
    # * the attribute is {#saved?}
    # * the attribute :update_only flag is not set
    #
    # @return [Boolean] whether this attribute is saved in a create operation
    def creatable?
      saved? and not @flags.include?(:update_only)
    end

    # A Java attribute is updatable if all of the following conditions hold:
    # * the attribute is {#saved?}
    # * the attribute :create_only flag is not set
    #
    # @return [Boolean] whether this attribute is saved in a update operation
    def updatable?
      saved? and not @flags.include?(:create_only)
    end

    # Indicates whether this reference propery is saved when its owner is saved.
    #
    # @return [Boolean] whether the attribute is a physical dependent or the +:cascaded+ flag is set
    def cascaded?
      (dependent? and not logical?) or @flags.include?(:cascaded)
    end
    
    # Determines whether this propery is included in a save operation argument.
    #
    # @return [Boolean] whether this attribute is {#cascaded?} or marked with the
    #   +:include_in_save_template+ flag
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
    
    # @return [Boolean] whether this attribute is #{#saved?} and does not have the
    #   +:nosync+ flag set
    def sync?
      saved? and not @flags.include?(:nosync)
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
    # declarer class can be created. An attribute is a savable prerequisite if it is
    # either:
    # * a {#cascaded?} dependent which does not #{#cascade_update_to_create?}, or
    # * a {#saved?} {#independent?} 1:M or M:N association.
    #
    # @return [Boolean] whether this attribute is a create prerequisite
    def savable_prerequisite?
      return true if cascaded? and @flags.include?(:no_cascade_update_to_create)
      return false unless independent? and saved?
      return true unless collection?
      inv_prop = inverse_property
      inv_prop.nil? or inv_prop.collection?
    end

    # @return [Boolean] whether the subject attribute is not saved
    def transient?
      not saved?
    end
    
    # @return [Boolean] whether this is a non-collection Java attribute
    def searchable?
      java_property? and not collection?
    end
         
    # @return [Boolean] whether this attribute is set by the server
    def volatile?
      to_sym == :identifier or @flags.include?(:volatile)
    end

    private
    
    # @param [Symbol] the flag to set
    # @return [Boolean] whether the flag is supported
    def flag_supported?(flag)
      super or SUPPORTED_FLAGS.include?(flag)
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
