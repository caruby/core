require 'caruby/util/collection'
require 'caruby/domain/merge'
require 'caruby/domain/attribute_metadata'

module CaRuby
  # ResourceMetadata mix-in for attribute accessors.
  module ResourceAttributes

    attr_reader :attributes, :defaults

    # Returns the subject class's required attributes, determined as follows:
    # * An attribute marked with the :mandatory flag is mandatory.
    # * An attribute marked with the :optional or :autogenerated flag is not mandatory.
    # * Otherwise, A secondary key or owner attribute is mandatory.
    attr_reader :mandatory_attributes

    # Adds the given attribute to this Class.
    # If attribute refers to a domain type, then the type argument is the referenced domain type.
    # Supported flags are listed in CaRuby::AttributeMetadata.
    def add_attribute(attribute, type=nil, *flags)
      add_attribute_metadata(AttributeMetadata.new(attribute, self, type, *flags))
      attribute
    end

    # Returns the +[:identifier]+ primary key attribute array.
    def primary_key_attributes
      IDENTIFIER_ATTR_ARRAY
    end

     # Returns this class's secondary key attribute array.
     # If this class's secondary key is not set, then the secondary key is the ResourceMetadata superclass
     # secondary key, if any.
    def secondary_key_attributes
      @scndy_key_attrs or superclass < Resource ? superclass.secondary_key_attributes : Array::EMPTY_ARRAY
    end

     # Returns this class's alternate key attribute array.
     # If this class's secondary key is not set, then the alternate key is the ResourceMetadata superclass
     # alternate key, if any.
    def alternate_key_attributes
      @alt_key_attrs or superclass < Resource ? superclass.alternate_key_attributes : Array::EMPTY_ARRAY
    end

    # @return the AttributeMetadata for the given attribute symbol or alias
    # @raise [NameError] if the attribute is not recognized
    def attribute_metadata(attribute)
      # simple and predominant case is that attribute is a standard attribute.
      # otherwise, resolve attribute to the standard symbol.
      attr_md = attribute_metadata_hash[attribute] || attribute_metadata_hash[standard_attribute(attribute)]
      # if not found, then delegate to handler which will either make the new attribute or raise a NameError
      attr_md || (attribute_missing(attribute) && @local_attr_md_hash[attribute])
    end

    # Returns the standard attribute symbol for the given name_or_alias.
    #
    # Raises NameError if the attribute is not found
    def standard_attribute(name_or_alias)
      alias_standard_attribute_hash[name_or_alias.to_sym] or raise NameError.new("#{qp} attribute not found: #{name_or_alias}")
    end

    # Returns an Enumerable on this Metadata's attributes which iterates on each attribute whose
    # corresponding AttributeMetadata satisfies the given filter block.
    def attribute_filter(&filter) # :yields: attribute_metadata
     Filter.new(attribute_metadata_hash, &filter)
    end

    ## the built-in Metadata attribute filters ##

    # @return [<Symbol>] the domain attributes which wrap a java property
    # @see AttributeMetadata#java_property?
    def java_attributes
      @java_attrs ||= attribute_filter { |attr_md| attr_md.java_property? }
    end

    # @return [<Symbol>] the domain attributes
    def domain_attributes
      @dom_attrs ||= attribute_filter { |attr_md| attr_md.domain? }
    end

    # @return [<Symbol>] the non-domain Java attributes
    def nondomain_attributes
      @nondom_attrs ||= attribute_filter { |attr_md| attr_md.java_property? and attr_md.nondomain? }
    end

    # @return [<Symbol>] the non-domain Java property wrapper attributes
    def nondomain_java_attributes
      @nondom_java_attrs ||= nondomain_attributes.compose { |attr_md| attr_md.java_property? }
    end

    # @return [<Symbol>] the standard attributes which can be merged into an instance of the subject class.
    #   The default mergeable attributes consist of the {#nondomain_java_attributes}.
    # @see Mergeable#mergeable_attributes
    alias :mergeable_attributes :nondomain_java_attributes

    # @return [<Symbol>] the dependent attributes
    def dependent_attributes
      @dep_attrs ||= attribute_filter { |attr_md| attr_md.dependent? }
    end

    # @return [<Symbol>] the dependent attributes
    def autogenerated_dependent_attributes
      @ag_dep_attrs ||= dependent_attributes.compose { |attr_md| attr_md.autogenerated? }
    end

    # @return [<Symbol>] the dependent attributes which are created but not fetched
    # @see AttributeMetadata#unfetched_created?
    def unfetched_created_attributes
      @uc_attrs ||= attribute_filter { |attr_md| attr_md.unfetched_created? }
    end

    # @return [<Symbol>] the autogenerated logical dependent attributes
    # @see #logical_dependent_attributes
    # @see AttributeMetadata#autogenerated?
    def autogenerated_logical_dependent_attributes
      @ag_log_dep_attrs ||= dependent_attributes.compose { |attr_md| attr_md.autogenerated? and attr_md.logical? }
    end
    
    # @return [<Symbol>] the autogenerated {AttributeMetadata#saved_mergeable?} dependent attributes
    def mergeable_saved_autogenerated_attributes
      @mgbl_sv_unftchd_ag_attrs ||= autogenerated_dependent_attributes.compose { |attr_md| attr_md.saved_mergeable? }
    end
    
    # @return [<Symbol>] the logical dependent attributes
    # @see AttributeMetadata#logical?
    def logical_dependent_attributes
      @log_dep_attrs ||= dependent_attributes.compose { |attr_md| attr_md.logical? }
    end
    
    def unidirectional_dependent_attributes
      @uni_dep_attrs ||= dependent_attributes.compose { |attr_md| attr_md.unidirectional? }
    end

    # @return [<Symbol>] the auto-generated attributes
    # @see AttributeMetadata#autogenerated?
    def autogenerated_attributes
      @ag_attrs ||= attribute_filter { |attr_md| attr_md.autogenerated? }
    end
    
    # @return [<Symbol>] the auto-generated non-domain attributes
    # @see AttributeMetadata#nondomain?
    # @see AttributeMetadata#autogenerated?
    def autogenerated_nondomain_attributes
      @ag_nd_attrs ||= attribute_filter { |attr_md| attr_md.autogenerated? and attr_md.nondomain? }
    end
    
    # @return [<Symbol>] the {AttributeMetadata#volatile?} non-domain attributes
    def volatile_nondomain_attributes
      @unsvd_nd_attrs ||= attribute_filter { |attr_md| attr_md.volatile? and attr_md.nondomain? }
    end

    # @return [<Symbol>] the domain attributes which can serve as a query parameter
    # @see AttributeMetadata#searchable?
    def searchable_attributes
      @srchbl_attrs ||= attribute_filter { |attr_md| attr_md.searchable? }
    end

    # @return [<Symbol>] the create/update cascaded domain attributes
    # @see AttributeMetadata#cascaded?
    def cascaded_attributes
      @cscd_attrs ||= domain_attributes.compose { |attr_md| attr_md.cascaded? }
    end

    # @return [<Symbol>] the {#cascaded_attributes} which are saved with a proxy
    #   using the dependent saver_proxy method
    def proxied_cascaded_attributes
      @px_cscd_attrs ||= cascaded_attributes.compose { |attr_md| attr_md.proxied_save? }
    end

    # @return [<Symbol>] the {#cascaded_attributes} which are not saved with a proxy
    #   using the dependent saver_proxy method
    def unproxied_cascaded_attributes
      @unpx_cscd_attrs ||= cascaded_attributes.compose { |attr_md| not attr_md.proxied_save? }
    end
    
    # Returns the physical or auto-generated logical dependent attributes that can
    # be copied from a save result to the given save argument object.
    #
    # @return [<Symbol>] the attributes that can be copied from a save result to a
    #  save argument object
    # @see AttributeMetadata#autogenerated?
    def copyable_saved_attributes
      @cp_sv_attrs ||= dependent_attributes.compose { |attr_md| attr_md.autogenerated? or not attr_md.logical? }
    end

    def mandatory_attributes
      @mndtry_attrs ||= collect_mandatory_attributes
    end

    # @return [<Symbol>] the attributes which are {AttributeMetadata#creatable?}
    def creatable_attributes
      @cr_attrs ||= attribute_filter { |attr_md| attr_md.creatable? }
    end

    # @return [<Symbol>] the attributes which are {AttributeMetadata#updatable?}
    def updatable_attributes
      @upd_attrs ||= attribute_filter { |attr_md| attr_md.updatable? }
    end

    def fetched_dependent_attributes
      @ftchd_dep_attrs ||= (fetched_domain_attributes & dependent_attributes).to_a
    end

    # @return [<Symbol>] the independent saved attributes
    # @see AttributeMetadata#independent?
    # @see AttributeMetadata#saved?
    def saved_independent_attributes
      @svd_ind_attrs ||= attribute_filter { |attr_md| attr_md.independent? and attr_md.saved? }
    end

    # @return [<Symbol>] the domain {AttributeMetadata#saved?} attributes
    def saved_domain_attributes
      @svd_dom_attrs ||= domain_attributes.compose { |attr_md| attr_md.saved? }
    end

    # @return [<Symbol>] the non-domain {AttributeMetadata#saved?} attributes
    def saved_nondomain_attributes
      @svd_nondom_attrs ||= nondomain_attributes.compose { |attr_md| attr_md.saved? }
    end

    # @return [<Symbol>] the {AttributeMetadata#volatile?} {#nondomain_attributes}
    def volatile_nondomain_attributes
      @vlt_nondom_attrs ||= nondomain_attributes.compose { |attr_md| attr_md.volatile? }
    end

    # @return [<Symbol>] the domain {#creatable_attributes}
    def creatable_domain_attributes
      @cr_dom_attrs ||= domain_attributes.compose { |attr_md| attr_md.creatable? }
    end

    # @return [<Symbol>] the domain {#updatable_attributes}
    def updatable_domain_attributes
      @upd_dom_attrs ||= domain_attributes.compose { |attr_md| attr_md.updatable? }
    end

    # @return [<Symbol>] the domain attributes whose referents must exist before an instance of this
    #   metadata's subject classcan be created
    # @see AttributeMetadata#storable_prerequisite?
    def storable_prerequisite_attributes
      @stbl_prereq_dom_attrs ||= attribute_filter { |attr_md| attr_md.storable_prerequisite? }
    end

    # @return [<Symbol>] the attributes which are populated from the database
    # @see AttributeMetadata#fetched?
    def fetched_attributes
      @ftchd_attrs ||= attribute_filter { |attr_md| attr_md.fetched? }
    end

    # Returns the domain attributes which are populated in a query on the given fetched instance of
    # this metadata's subject class. The domain attribute is fetched if it satisfies the following 
    # conditions:
    # * the attribute is a dependent attribute or of abstract domain type
    # * the attribute is not specified as unfetched in the configuration
    #
    # @return [<Symbol>] the attributes which are {AttributeMetadata#fetched?}
    def fetched_domain_attributes
      @ftchd_dom_attrs ||= domain_attributes.compose { |attr_md| attr_md.fetched? }
    end

    #@return [<Symbol>] the #domain_attributes which are not #fetched_domain_attributes
    def unfetched_domain_attributes
      @unftchd_attrs ||= domain_attributes.compose { |attr_md| not attr_md.fetched? }
    end

    # @return [<Symbol>] the Java property non-abstract {#unfetched_domain_attributes}
    def loadable_attributes
      @unftchd_attrs ||= unfetched_domain_attributes.compose { |attr_md| attr_md.java_property? and not attr_md.type.abstract? }
    end

    # @return [<Symbol>] the {#loadable_attributes} which are not {AttributeMetadata#autogenerated?}
    def non_autogenerated_loadable_attributes
      @unftchd_attrs ||= unfetched_domain_attributes.compose { |attr_md| not attr_md.type.autogenerated? }
    end

    # @param [Symbol] attribute the attribute to check
    # @return [Boolean] whether attribute return type is a domain object or collection thereof
    def domain_attribute?(attribute)
      attribute_metadata(attribute).domain?
    end

    # @param [Symbol] attribute the attribute to check
    # @return [Boolean] whether attribute is not a domain attribute
    def nondomain_attribute?(attribute)
      not domain_attribute?(attribute)
    end

    # @param [Symbol] attribute the attribute to check
    # @return [Boolean] whether attribute is an instance of a Java domain class
    def collection_attribute?(attribute)
      attribute_metadata(attribute).collection?
    end

    protected

    # @return [{Symbol => AttributeMetadata}] the attribute => metadata hash
    def attribute_metadata_hash
      # initialize the meta-data if necessary
      superclass.introspect_subclass(self) if @attr_md_hash.nil?
      @attr_md_hash
    end

    # @return [{Symbol => Symbol}] the attribute alias => standard hash
    def alias_standard_attribute_hash
      # initialize the meta-data if necessary
      superclass.introspect_subclass(self) if @alias_std_attr_map.nil?
      @alias_std_attr_map
    end

    private

    IDENTIFIER_ATTR_ARRAY = [:identifier]

    # A filter on the standard attribute symbol => metadata hash that yields
    # each attribute which satisfies the attribute metadata condition.
    class Filter
      include Enumerable

      # @param [{Symbol => AttributeMetadata}] hash the attribute symbol => metadata hash
      # @yield [attr_md] condition which determines whether the attribute is selected
      # @yieldparam [AttributeMetadata] the metadata for the standard attribute
      def initialize(hash, &filter)
        raise ArgumentError.new("Attribute filter missing hash argument") if hash.nil?
        raise ArgumentError.new("Attribute filter missing filter block") unless block_given?
        @hash = hash
        @filter = filter
      end

      # @yield [attribute] enumerates each filtered attribute
      # @yieldparam [Symbol] the attribute which satisfies the filter condition
      def each(&block)
        @hash.each { |k, v| yield(k) if @filter.call(v) }
      end

      # @return [Filter] a new Filter which applies the filter block given to this
      #   method with the AttributeMetadata enumerated by this filter.
      def compose
        Filter.new(@hash) { |attr_md| @filter.call(attr_md) and yield(attr_md) }
      end
    end

    # Initializes the attribute meta-data structures.
    def init_attributes
      @local_std_attr_hash = {}
      @alias_std_attr_map = append_parent_enum(@local_std_attr_hash) { |par| par.alias_standard_attribute_hash }
      @local_attr_md_hash = {}
      @attr_md_hash = append_parent_enum(@local_attr_md_hash) { |par| par.attribute_metadata_hash }
      @attributes = Enumerable::Enumerator.new(@attr_md_hash, :each_key)
      @local_mndty_attrs = Set.new
      @local_defaults = {}
      @defaults = append_parent_enum(@local_defaults) { |par| par.defaults }
    end

    def add_attribute_aliases(hash)
      hash.each { |aliaz, attr| delegate_to_attribute(aliaz, attr) }
    end

    # Sets this class's secondary key attributes to the given attributes.
    # If attributes is set to nil, then the secondary key is cleared.
    def set_secondary_key_attributes(*attributes)
      attributes.compact!
      @scndy_key_attrs = attributes.map { |attr| standard_attribute(attr) }
    end

    # Sets this class's alternate key attributes to the given attributes.
    # If attributes is set to nil, then the alternate key is cleared.
    def set_alternate_key_attributes(*attributes)
      attributes.compact!
      @alt_key_attrs = attributes.map { |attr| standard_attribute(attr) }
    end

    # Sets the given attribute type to klass. If attribute is defined in a superclass,
    # then klass must be a subclass of the superclass attribute type.
    #
    # Raises ArgumentError if klass is incompatible with the current attribute type.
    def set_attribute_type(attribute, klass)
      attr_md = attribute_metadata(attribute)
      if attr_md.declarer == self then
        attr_md.type = klass
      elsif attr_md.type.nil? or klass < attr_md.type then
        new_attr_md = attr_md.restrict(self, klass)
        add_attribute_metadata(new_attr_md)
      elsif klass != attr_md.type then
        raise ArgumentError.new("Cannot reset #{qp}.#{attribute} type #{attr_md.type} to incompatible #{klass.qp}")
      end
    end

    # Sets the given attribute inverse to the inverse symbol.
    #
    # Raises ArgumentError if the inverse type is incompatible with this Resource.
    def set_attribute_inverse(attribute, inverse)
      attr_md = attribute_metadata(attribute)
      # return if inverse is already set
      return if attr_md.inverse == inverse
      # the inverse attribute meta-data
      inv_md = attr_md.type.attribute_metadata(inverse)
      # if the attribute is the many side of a 1:M relation, then delegate to the one side.
      if attr_md.collection? and not inv_md.collection? then
        return attr_md.type.set_attribute_inverse(inverse, attribute)
      end
      # this class must be the same as or a subclass of the inverse attribute type
      unless self <= inv_md.type then
        raise ArgumentError.new("Cannot set #{qp}.#{attribute} inverse to #{attr_md.type.qp}.#{attribute} with incompatible type #{inv_md.type.qp}")
      end

      # if the attribute is defined by this class, then set the inverse in the attribute metadata.
      # otherwise, make a new attribute metadata specialized for this class.
      unless attr_md.declarer == self then
        attr_md = attr_md.dup
        attr_md.declarer = self
        add_attribute_metadata(attribute, inverse)
      end
      attr_md.inverse = inverse

      # if attribute is the one side of a 1:M relation, then add the inverse updater.
      unless attr_md.collection? then
        add_inverse_updater(attribute, inverse)
      end
    end

    def add_attribute_defaults(hash)
      hash.each { |attr, value| @local_defaults[standard_attribute(attr)] = value }
    end

    def add_mandatory_attributes(*attributes)
      attributes.each { |attr| @local_mndty_attrs << standard_attribute(attr) }
    end

    # Marks the given attribute with flags supported by {AttributeMetadata#qualify}.
    def qualify_attribute(attribute, *flags)
      attribute_metadata(attribute).qualify(*flags)
    end

    # Removes the given attribute from this Resource.
    # An attribute declared in a superclass Resource is hidden from this Resource but retained in
    # the declaring Resource.
    def remove_attribute(attribute)
      std_attr = standard_attribute(attribute)
      # if the attribute is local, then delete it, otherwise filter out the superclass attribute
      if @local_attr_md_hash.delete(std_attr) then
        @local_mndty_attrs.delete(std_attr)
        @local_std_attr_hash.delete_if { |aliaz, attr| attr == std_attr }
      else
        @attr_md_hash = attribute_metadata_hash.filter_on_key { |attr| attr != attribute }
        @attributes = Enumerable::Enumerator.new(@attr_md_hash, :each_key)
        @alias_std_attr_map = alias_standard_attribute_hash.filter_on_key { |attr| attr != attribute }
      end
    end

    def add_attribute_metadata(attr_md)
      symbol = attr_md.to_sym
      @local_attr_md_hash[symbol] = attr_md
      # map the attribute symbol to itself in the alias map
      @local_std_attr_hash[symbol] = symbol
    end

    # Records that the given aliaz aliases a standard attribute.
    def add_alias(aliaz, attribute)
      std_attr = standard_attribute(attribute)
      raise ArgumentError.new("#{self} attribute not found: #{attribute}") if std_attr.nil?
      @local_std_attr_hash[aliaz.to_sym] = std_attr
    end

    # Returns a new Enumerable which appends the evaluation of the given block in the parent
    # metadata context. The default enum is the evaluation of the given block on this Metadata.
    def append_parent_enum(enum)
      superclass < Resource ? enum.union(yield(superclass)) : enum
    end

    def each_attribute_metadata(&block)
      attribute_metadata_hash.each_value(&block)
    end

    # Collects the {AttributeMetadata#fetched_dependent?} and {AttributeMetadata#fetched_independent?}
    # standard domain attributes.
    #
    # @return [<Symbol>] the fetched attributes
    def collect_default_fetched_domain_attributes
      attribute_filter do |attr_md|
        if attr_md.domain? then
          attr_md.dependent? ? fetched_dependent?(attr_md) : fetched_independent?(attr_md)
        end
      end
    end

    # Merges the secondary key, owner and additional mandatory attributes defined in the properties.
    #
    # @see #mandatory_attributes
    def collect_mandatory_attributes
      mandatory = Set.new
      # add the secondary key
      mandatory.merge(secondary_key_attributes)
      # add the owner attribute, if any
      mandatory << owner_attribute unless owner_attribute.nil? or not attribute_metadata(owner_attribute).java_property?
      # remove autogenerated or optional attributes
      mandatory.delete_if { |attr| attribute_metadata(attr).autogenerated? or attribute_metadata(attr).optional? }
      @local_mndty_attrs.merge!(mandatory)
      append_parent_enum(@local_mndty_attrs) { |par| par.mandatory_attributes }
    end

    # Raises a NameError. Domain classes can override this method to dynamically create a new reference attribute.
    #
    # @raise [NameError] always
    def attribute_missing(attribute)
      raise NameError.new("#{name.demodulize} attribute not found: #{attribute}")
    end
  end
end