require 'enumerator'
require 'jinx/helpers/collections'

require 'jinx/metadata/property'
require 'jinx/metadata/pattribute_enumerator'

module Jinx
  # Meta-data mix-in for attribute accessors.
  module Properties
    # @return [<Symbol>] this class's attributes
    attr_reader :attributes
    
    # @return [Hashable] the default attribute => value associations
    attr_reader :defaults

    # Returns whether this class has an attribute with the given symbol.
    #
    # @param [Symbol] symbol the potential attribute
    # @return [Boolean] whether there is a corresponding attribute
    def property_defined?(symbol)
      unless Symbol === symbol then
        Jinx.fail(ArgumentError, "Property argument #{symbol.qp} of type #{symbol.class.qp} is not a symbol")
      end
      !!@alias_std_prop_map[symbol.to_sym]
    end

    # Adds the given attribute to this Class.
    #
    # @param [Symbol] attribute the attribute to add
    # @param [Class] type (see Property#initialize)
    # @param flags (see Property#initialize)
    # @return [Property] the attribute meta-data
    def add_attribute(attribute, type, *flags)
      prop = Property.new(attribute, self, type, *flags)
      add_property(prop)
      prop
    end
    
    # Adds the given attribute restriction to this Class.
    # This method is intended for the exclusive use of {Property.restrict}.
    # Clients restrict an attribute by calling that method.
    #
    # @param [Property] attribute the restricted attribute
    def add_restriction(attribute)
      add_property(attribute)
      logger.debug { "Added restriction #{attribute} to #{qp}." }
    end

    # @return [<Symbol>] the primary key attributes
    def primary_key_attributes
      @prm_key or Class === self && superclass < Resource ? superclass.primary_key_attributes : Array::EMPTY_ARRAY
    end

    # Returns this class's secondary key attribute array.
    # If this class's secondary key is not set, then the secondary key is the Metadata superclass
    # secondary key, if any.
    #
    # @return [<Symbol>] the secondary key attributes
    def secondary_key_attributes
      @scnd_key or Class === self && superclass < Resource ? superclass.secondary_key_attributes : Array::EMPTY_ARRAY
    end

    # Returns this class's alternate key attribute array.
    # If this class's secondary key is not set, then the alternate key is the {Metadata} superclass
    # alternate key, if any.
    #
    # @return [<Symbol>] the alternate key attributes
    def alternate_key_attributes
      @alt_key or superclass < Resource ? superclass.alternate_key_attributes : Array::EMPTY_ARRAY
    end
    
    # @return [<Symbol>] the primary, secondary and alternate key attributes
    def all_key_attributes
      primary_key_attributes + secondary_key_attributes + alternate_key_attributes
    end

    # @yield [prop] operate on the given property
    # @yieldparam [Property] prop the property in this class
    def each_property(&block)
      @prop_hash.each_value(&block)
    end

    # @return the Property for the given attribute symbol or alias
    # @raise [NameError] if the attribute is not recognized
    def property(attribute)
      # Simple and predominant case is that the attribute is a standard attribute.
      # Otherwise, resolve attribute to the standard symbol.
      prop = @prop_hash[attribute] || @prop_hash[standard_attribute(attribute)]
      # If not found, then raise a NameError.
      if prop.nil? then
        Jinx.fail(NameError, "#{name.demodulize} attribute not found: #{attribute}")
      end
      prop
    end

    # @param [Symbol, String] name_or_alias the attribute name or alias
    # @return [Symbol] the standard attribute symbol for the given name or alias
    # @raise [ArgumentError] if the attribute name or alias argument is missing
    # @raise [NameError] if the attribute is not found
    def standard_attribute(name_or_alias)
      if name_or_alias.nil? then
        Jinx.fail(ArgumentError, "#{qp} standard attribute call is missing the attribute name/alias parameter")
      end
      @alias_std_prop_map[name_or_alias.to_sym] or Jinx.fail(NameError, "#{self} attribute not found: #{name_or_alias}")
    end

    ## Metadata ATTRIBUTE FILTERS ##

    # @return [<Symbol>] the domain attributes which wrap a java attribute
    # @see Property#java_property?
    def java_attributes
      @java_flt ||= attribute_filter { |prop| prop.java_property? }
    end

    alias :printable_attributes :java_attributes

    # @return [<Symbol>] the domain attributes
    def domain_attributes
      @dom_flt ||= attribute_filter { |prop| prop.domain? }
    end

    # @return [<Symbol>] the non-domain Java attributes
    def nondomain_attributes
      @ndom_flt ||= attribute_filter { |prop| prop.java_property? and prop.nondomain? }
    end

    # @return [<Symbol>] the non-domain Java attribute wrapper attributes
    def nondomain_java_attributes
      @ndom_java_flt ||= nondomain_attributes.compose { |prop| prop.java_property? }
    end

    # @return [<Symbol>] the standard attributes which can be merged into an instance of the subject class.
    #   The default mergeable attributes consist of the {#nondomain_java_attributes}.
    # @see Mergeable#mergeable_attributes
    alias :mergeable_attributes :nondomain_java_attributes

    # @param [Boolean, nil] inc_super flag indicating whether to include dependents defined in the superclass
    # @return [<Symbol>] the dependent attributes
    def dependent_attributes(inc_super=true)
      if inc_super then
        @dep_flt ||= attribute_filter { |prop| prop.dependent? }
      else
        @local_dep_flt ||= dependent_attributes.compose { |prop| prop.declarer == self }
      end
    end

    # @return [<Symbol>] the dependent attributes
    def autogenerated_dependent_attributes
      @ag_dep_flt ||= dependent_attributes.compose { |prop| prop.autogenerated? }
    end

    # @return [<Symbol>] the autogenerated logical dependent attributes
    # @see #logical_dependent_attributes
    # @see Property#autogenerated?
    def autogenerated_logical_dependent_attributes
      @ag_log_dep_flt ||= dependent_attributes.compose { |prop| prop.autogenerated? and prop.logical? }
    end
    
    # @return [<Symbol>] the {Property#fetch_saved?} attributes
    def saved_attributes_to_fetch
      @sv_ftch_flt ||= domain_attributes.compose { |prop| prop.fetch_saved? }
    end
    
    # @return [<Symbol>] the logical dependent attributes
    # @see Property#logical?
    def logical_dependent_attributes
      @log_dep_flt ||= dependent_attributes.compose { |prop| prop.logical? }
    end
    
    # @return [<Symbol>] the unidirectional dependent attributes
    # @see Property#unidirectional?
    def unidirectional_dependent_attributes
      @uni_dep_flt ||= dependent_attributes.compose { |prop| prop.unidirectional? }
    end

    # @return [<Symbol>] the auto-generated attributes
    # @see Property#autogenerated?
    def autogenerated_attributes
      @ag_flt ||= attribute_filter { |prop| prop.autogenerated? }
    end
    
    # @return [<Symbol>] the auto-generated non-domain attributes
    # @see Property#nondomain?
    # @see Property#autogenerated?
    def autogenerated_nondomain_attributes
      @ag_nd_flt ||= attribute_filter { |prop| prop.autogenerated? and prop.nondomain? }
    end
    
    # @return [<Symbol>] the {Property#volatile?} non-domain attributes
    def volatile_nondomain_attributes
      @unsvd_nd_flt ||= attribute_filter { |prop| prop.volatile? and prop.nondomain? }
    end

    # @return [<Symbol>] the domain attributes which can serve as a query parameter
    # @see Property#searchable?
    def searchable_attributes
      @srchbl_flt ||= attribute_filter { |prop| prop.searchable? }
    end

    # @return [<Symbol>] the create/update cascaded domain attributes
    # @see Property#cascaded?
    def cascaded_attributes
      @cscd_flt ||= domain_attributes.compose { |prop| prop.cascaded? }
    end

    # @return [<Symbol>] the {#cascaded_attributes} which are saved with a proxy
    #   using the dependent saver_proxy method
    def proxied_savable_template_attributes
      @px_cscd_flt ||= savable_template_attributes.compose { |prop| prop.proxied_save? }
    end

    # @return [<Symbol>] the {#cascaded_attributes} which do not have a
    #   #{Property#proxied_save?}
    def unproxied_savable_template_attributes
      @unpx_sv_tmpl_flt ||= savable_template_attributes.compose { |prop| not prop.proxied_save? }
    end

    # @return [<Symbol>] the {#domain_attributes} to {Property#include_in_save_template?}
    def savable_template_attributes
      @sv_tmpl_flt ||= domain_attributes.compose { |prop| prop.include_in_save_template? }
    end
    
    # Returns the physical or auto-generated logical dependent attributes that can
    # be copied from a save result to the given save argument object.
    #
    # @return [<Symbol>] the attributes that can be copied from a save result to a
    #  save argument object
    # @see Property#autogenerated?
    def copyable_saved_attributes
      @cp_sv_flt ||= dependent_attributes.compose { |prop| prop.autogenerated? or not prop.logical? }
    end

    # Returns the subject class's required attributes, determined as follows:
    # * An attribute marked with the :mandatory flag is mandatory.
    # * An attribute marked with the :optional or :autogenerated flag is not mandatory.
    # * Otherwise, A secondary key or owner attribute is mandatory.
    def mandatory_attributes
      @mnd_flt ||= collect_mandatory_attributes
    end

    # @return [<Symbol>] the attributes which are {Property#creatable?}
    def creatable_attributes
      @cr_flt ||= attribute_filter { |prop| prop.creatable? }
    end

    # @return [<Symbol>] the attributes which are {Property#updatable?}
    def updatable_attributes
      @upd_flt ||= attribute_filter { |prop| prop.updatable? }
    end

    def fetched_dependent_attributes
      @fch_dep_flt ||= (fetched_domain_attributes & dependent_attributes).to_a
    end
    
    def nonowner_attributes
      @nownr_atts ||= attribute_filter { |prop| not prop.owner? }
    end
    
    # @return [<Symbol>] the saved dependent attributes
    # @see Property#dependent?
    # @see Property#saved?
    def saved_dependent_attributes
      @sv_dep_flt ||= attribute_filter { |prop| prop.dependent? and prop.saved? }
    end
    
    # @return [<Symbol>] the saved independent attributes
    # @see Property#independent?
    # @see Property#saved?
    def independent_attributes
      @ind_flt ||= attribute_filter { |prop| prop.independent? }
    end
    
    # @return [<Symbol>] the saved independent attributes
    # @see Property#independent?
    # @see Property#saved?
    def saved_independent_attributes
      @sv_ind_flt ||= attribute_filter { |prop| prop.independent? and prop.saved? }
    end

    # @return [<Symbol>] the domain {Property#sync?} attributes
    def sync_domain_attributes
      @sync_dom_flt ||= domain_attributes.compose { |prop| prop.sync? }
    end

    # @return [<Symbol>] the non-domain {Property#saved?} attributes
    def saved_nondomain_attributes
      @sv_ndom_flt ||= nondomain_attributes.compose { |prop| prop.saved? }
    end

    # @return [<Symbol>] the {Property#volatile?} {#nondomain_attributes}
    def volatile_nondomain_attributes
      @vl_ndom_flt ||= nondomain_attributes.compose { |prop| prop.volatile? }
    end

    # @return [<Symbol>] the domain {#creatable_attributes}
    def creatable_domain_attributes
      @cr_dom_flt ||= domain_attributes.compose { |prop| prop.creatable? }
    end

    # @return [<Symbol>] the domain {#updatable_attributes}
    def updatable_domain_attributes
      @upd_dom_flt ||= domain_attributes.compose { |prop| prop.updatable? }
    end

    # @return [<Symbol>] the attributes which are populated from the database
    # @see Property#fetched?
    def fetched_attributes
      @fch_flt ||= attribute_filter { |prop| prop.fetched? }
    end

    # Returns the domain attributes which are populated in a query on the given fetched instance of
    # this metadata's subject class. The domain attribute is fetched if it satisfies the following 
    # conditions:
    # * the attribute is a dependent attribute or of abstract domain type
    # * the attribute is not specified as unfetched in the configuration
    #
    # @return [<Symbol>] the attributes which are {Property#fetched?}
    def fetched_domain_attributes
      @fch_dom_flt ||= domain_attributes.compose { |prop| prop.fetched? }
    end

    #@return [<Symbol>] the #domain_attributes which are not #fetched_domain_attributes
    def unfetched_attributes
      @unftchd_flt ||= domain_attributes.compose { |prop| not prop.fetched? }
    end
    
    alias :toxic_attributes :unfetched_attributes

    # @return [<Symbol>] the Java attribute non-abstract {#unfetched_attributes}
    def loadable_attributes
      @ld_flt ||= unfetched_attributes.compose { |prop| prop.java_property? and not prop.type.abstract? }
    end

    # @param [Symbol] attribute the attribute to check
    # @return [Boolean] whether attribute return type is a domain object or collection thereof
    def domain_attribute?(attribute)
      property(attribute).domain?
    end

    # @param [Symbol] attribute the attribute to check
    # @return [Boolean] whether attribute is not a domain attribute
    def nondomain_attribute?(attribute)
      not domain_attribute?(attribute)
    end

    # @param [Symbol] attribute the attribute to check
    # @return [Boolean] whether attribute is an instance of a Java domain class
    def collection_attribute?(attribute)
      property(attribute).collection?
    end

    protected
    
    # @return [{Symbol => Property}] the attribute => metadata hash
    def property_hash
      @prop_hash
    end

    # @return [{Symbol => Symbol}] the attribute alias => standard hash
    def alias_standard_attribute_hash
      @alias_std_prop_map
    end

    private
    
    # Returns the most specific attribute which references the given target type, or nil if none.
    # If the given class can be returned by more than on of the attributes, then the attribute
    # is chosen whose return type most closely matches the given class.
    #
    # @param [Class] klass the target type
    # @param [Filter, nil] attributes the attributes to check (default all domain attributes)
    # @return [Symbol, nil] the most specific reference attribute, or nil if none
    def most_specific_domain_attribute(klass, attributes=nil)
      attributes ||= domain_attributes
      candidates = attributes.properties
      best = candidates.inject(nil) do |better, prop|
        # If the attribute can return the klass then the return type is a candidate.
        # In that case, the klass replaces the best candidate if it is more specific than
        # the best candidate so far.
        klass <= prop.type ? (better && better.type <= prop.type ? better : prop) : better
      end
      if best then
        logger.debug { "Most specific #{qp} -> #{klass.qp} reference from among #{candidates.qp} is #{best.declarer.qp}.#{best}." }
        best.to_sym
      end
    end
    
    # Returns an Enumerable on this Resource class's attributes which iterates on each attribute whose
    # corresponding Property satisfies the given filter block.
    #
    # @yield [prop] the attribute selector
    # @yieldparam [Property] prop the candidate attribute
    # @return [Filter] an {Property} enumerator
    def attribute_filter(&filter)
      # make the attribute filter
      raise MetadataError.new("#{self} has not been introspected") if @prop_hash.nil?
      Filter.new(self, @prop_hash, &filter)
    end

    # Initializes the property meta-data structures.
    def init_property_classifiers
      @local_std_prop_hash = {}
      @alias_std_prop_map = append_ancestor_enum(@local_std_prop_hash) { |par| par.alias_standard_attribute_hash }
      @local_prop_hash = {}
      @prop_hash = append_ancestor_enum(@local_prop_hash) { |par| par.property_hash }
      @attributes = Enumerable::Enumerator.new(@prop_hash, :each_key)
      @local_mndty_flt = Set.new
      @local_defaults = {}
      @defaults = append_ancestor_enum(@local_defaults) { |par| par.defaults }
    end
    
    # Detects the first attribute with the given type.
    #
    # @param [Class] klass the target attribute type
    # @return [Symbol, nil] the attribute with the given type
    def detect_attribute_with_type(klass)
      property_hash.detect_key_with_value { |prop| prop.type == klass }
    end
    
    # Creates the given attribute alias. If the attribute metadata is registered with this class, then
    # this method overrides +Class.alias_attribute+ to create a new alias reader (writer) method
    # which delegates to the attribute reader (writer, resp.). This aliasing mechanism differs from
    # {Class#alias_attribute}, which directly aliases the existing reader or writer method.
    # Delegation allows the alias to pick up run-time redefinitions of the aliased reader and writer.
    # If the attribute metadata is not registered with this class, then this method delegates to
    # {Class#alias_attribute}.
    #
    # @param [Symbol] aliaz the attribute alias
    # @param [Symbol] attribute the attribute to alias
    def alias_attribute(aliaz, attribute)
      if property_defined?(attribute) then
        delegate_to_attribute(aliaz, attribute)
        register_property_alias(aliaz, attribute)
      else
        super
      end
    end

    # Creates the given aliases to attributes.
    #
    # @param [{Symbol => Symbol}] hash the alias => attribute hash
    # @see #attribute_alias
    # @deprecated Use {#alias_attribute} instead
    def add_attribute_aliases(hash)
      hash.each { |aliaz, pa| alias_attribute(aliaz, pa) }
    end

    # Adds the given attribute to this class's primary key.
    def add_primary_key_attribute(attribute)
      @prm_key ||= []
      @prm_key << standard_attribute(attribute)
    end

    # Sets this class's primary key attributes to the given attributes.
    # If attributes is set to nil, then the primary key is cleared.
    def set_primary_key_attributes(*attributes)
      attributes.each { |a| add_primary_key_attribute(a) }
    end

    # Adds the given attribute to this class's secondary key.
    def add_secondary_key_attribute(attribute)
      @scnd_key ||= []
      @scnd_key << standard_attribute(attribute)
    end

    # Sets this class's secondary key attributes to the given attributes.
    # If attributes is set to nil, then the secondary key is cleared.
    def set_secondary_key_attributes(*attributes)
      attributes.each { |a| add_secondary_key_attribute(a) }
    end

    # Adds the given attribute to this class's alternate key.
    def add_alternate_key_attribute(attribute)
      @alt_key ||= []
      @alt_key << standard_attribute(attribute)
    end

    # Sets this class's alternate key attributes to the given attributes.
    # If attributes is set to nil, then the alternate key is cleared.
    def set_alternate_key_attributes(*attributes)
      attributes.each { |a| add_alternate_key_attribute(a) }
    end

    # Sets the given attribute type to klass. If attribute is defined in a superclass,
    # then klass must be a subclass of the superclass attribute type.
    #
    # @param [Symbol] attribute the attribute to modify
    # @param [Class] klass the attribute type
    # @raise [ArgumentError] if the new type is incompatible with the current attribute type
    def set_attribute_type(attribute, klass)
      prop = property(attribute)
      # degenerate no-op case
      return if klass == prop.type
      # If this class is the declarer, then simply set the attribute type.
      # Otherwise, if the attribute type is unspecified or is a superclass of the given class,
      # then make a new attribute metadata for this class.
      if prop.declarer == self then
        prop.type = klass
        logger.debug { "Set #{qp}.#{attribute} type to #{klass.qp}." }
      elsif prop.type.nil? or klass < prop.type then
        prop.restrict(self, :type => klass)
        logger.debug { "Restricted #{prop.declarer.qp}.#{attribute}(#{prop.type.qp}) to #{qp} with return type #{klass.qp}." }
      else
        Jinx.fail(ArgumentError, "Cannot reset #{qp}.#{attribute} type #{prop.type.qp} to incompatible #{klass.qp}")
      end
    end

    # @param [Hash] hash the attribute => value defaults
    def add_attribute_defaults(hash)
      hash.each { |da, value| add_attribute_default(da, value) }
    end

    # @param [Symbol] attribute the attribute
    # @param value the default value
    def add_attribute_default(attribute, value)
      @local_defaults[standard_attribute(attribute)] = value
    end

    # @param [<Symbol>] attributes the mandatory attributes
    def add_mandatory_attributes(*attributes)
      attributes.each { |ma| add_mandatory_attribute(ma) }
    end

    # @param [Symbol] attribute the mandatory attribute
    def add_mandatory_attribute(attribute)
      @local_mndty_flt << standard_attribute(attribute)
    end

    # Marks the given attribute with flags supported by {Property#qualify}.
    #
    # @param [Symbol] attribute the attribute to qualify
    # @param [{Symbol => Object}] the flags to apply to the restricted attribute
    def qualify_attribute(attribute, *flags)
      prop = property(attribute)
      if prop.declarer == self then
        prop.qualify(*flags)
      else
        logger.debug { "Restricting #{prop.declarer.qp}.#{attribute} to #{qp} with additional flags #{flags.to_series}" }
        prop.restrict_flags(self, *flags)
      end
    end

    # Removes the given attribute from this Resource.
    # An attribute declared in a superclass Resource is hidden from this Resource but retained in
    # the declaring Resource.
    def remove_attribute(attribute)
      std_prop = standard_attribute(attribute)
      # if the attribute is local, then delete it, otherwise filter out the superclass attribute
      prop = @local_prop_hash.delete(std_prop)
      if prop then
        # clear the inverse, if any
        prop.inverse = nil
        # remove from the mandatory attributes, if necessary
        @local_mndty_flt.delete(std_prop)
        # remove from the attribute => metadata hash
        @local_std_prop_hash.delete_if { |aliaz, pa| pa == std_prop }
      else
        # Filter the superclass hashes.
        anc_prop_hash = @prop_hash.components[1]
        @prop_hash.components[1] = anc_prop_hash.filter_on_key { |pa| pa != attribute }
        anc_alias_hash = @alias_std_prop_map.components[1]
        @alias_std_prop_map.components[1] = anc_alias_hash.filter_on_key { |pa| pa != attribute }
      end
    end

    # @param [Property] the property to add
    def add_property(property)
      pa = property.attribute
      @local_prop_hash[pa] = property
      # map the attribute symbol to itself in the alias map
      @local_std_prop_hash[pa] = pa
    end

    # Registers an alias to an attribute.
    #
    # @param (see #alias_attribute)
    def register_property_alias(aliaz, attribute)
      std = standard_attribute(attribute)
      Jinx.fail(ArgumentError, "#{self} attribute not found: #{attribute}") if std.nil?
      @local_std_prop_hash[aliaz.to_sym] = std
    end

    # Appends to the given enumerable the result of evaluating the block given to this method
    # on the superclass, if the superclass is in the same parent module as this class.
    #
    # @param [Enumerable] enum the base collection
    # @return [Enumerable] the {Enumerable#union} of the base collection with the superclass
    #   collection, if applicable 
    def append_ancestor_enum(enum)
      return enum unless Class === self and superclass.parent_module == parent_module
      anc_enum = yield superclass
      if anc_enum.nil? then
        Jinx.fail(MetadataError, "#{qp} superclass #{superclass.qp} does not have required metadata")
      end
      enum.union(anc_enum)
    end

    # Collects the {Property#fetched_dependent?} and {Property#fetched_independent?}
    # standard domain attributes.
    #
    # @return [<Symbol>] the fetched attributes
    def collect_default_fetched_domain_attributes
      attribute_filter do |prop|
        if prop.domain? then
          prop.dependent? ? fetched_dependent?(prop) : fetched_independent?(prop)
        end
      end
    end

    # Merges the secondary key, owner and additional mandatory attributes defined in the attributes.
    #
    # @see #mandatory_attributes
    def collect_mandatory_attributes
      mandatory = Set.new
      # add the secondary key
      mandatory.merge(secondary_key_attributes)
      # add the owner attribute, if any
      oa = mandatory_owner_attribute
      mandatory << oa if oa
      # remove autogenerated or optional attributes
      mandatory.delete_if { |ma| property(ma).autogenerated? or property(ma).flags.include?(:optional) }
      @local_mndty_flt.merge!(mandatory)
      append_ancestor_enum(@local_mndty_flt) { |par| par.mandatory_attributes }
    end
    
    # @return [Symbol, nil] the unique non-self-referential owner attribute, if one exists
    def mandatory_owner_attribute
      oa = owner_attribute || return
      prop = property(oa)
      oa if prop.java_property? and prop.type != self
    end
  end
end