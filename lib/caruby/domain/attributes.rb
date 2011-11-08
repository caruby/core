require 'enumerator'
require 'caruby/helpers/collection'
require 'caruby/domain/merge'
require 'caruby/domain/attribute'

module CaRuby
  module Domain
    # Meta-data mix-in for attribute accessors.
    module Attributes
      # @return [<Symbol>] this class's attributes
      attr_reader :attributes
      
      # @return [Hashable] the default attribute => value associations
      attr_reader :defaults
  
      # Returns whether this class has an attribute with the given symbol.
      #
      # @param [Symbol] symbol the potential attribute
      # @return [Boolean] whether there is a corresponding attribute
      def attribute_defined?(symbol)
        unless Symbol === symbol then
          raise ArgumentError.new("Attribute argument #{symbol.qp} of type #{symbol.class.qp} is not a symbol")
        end
        @attr_md_hash.has_key?(symbol)
      end
  
      # Adds the given attribute to this Class.
      #
      # @param [Symbol] attribute the attribute to add
      # @param [Class] type (see Attribute#initialize)
      # @param flags (see Attribute#initialize)
      # @return [Attribute] the attribute meta-data
      def add_attribute(attribute, type, *flags)
        attr_md = Attribute.new(attribute, self, type, *flags)
        add_attribute_metadata(attr_md)
        attr_md
      end
      
      # Adds the given attribute restriction to this Class.
      # This method is intended for the exclusive use of {Attribute.restrict}.
      # Clients restrict an attribute by calling that method.
      #
      # @param [Attribute] attribute the restricted attribute
      def add_restriction(attribute)
        add_attribute_metadata(attr_md)
        logger.debug { "Added restriction #{attribute} to #{qp}." }
      end
  
      # @return [(Symbol)] the +[:identifier]+ primary key attribute singleton array
      def primary_key_attributes
        IDENTIFIER_ATTR_ARRAY
      end
  
      # Returns this class's secondary key attribute array.
      # If this class's secondary key is not set, then the secondary key is the Metadata superclass
      # secondary key, if any.
      #
      # @return [<Symbol>] the secondary key attributes
      def secondary_key_attributes
        @scndy_key_attrs or superclass < Resource ? superclass.secondary_key_attributes : Array::EMPTY_ARRAY
      end
  
      # Returns this class's alternate key attribute array.
      # If this class's secondary key is not set, then the alternate key is the {Metadata} superclass
      # alternate key, if any.
      #
      # @return [<Symbol>] the alternate key attributes
      def alternate_key_attributes
        @alt_key_attrs or superclass < Resource ? superclass.alternate_key_attributes : Array::EMPTY_ARRAY
      end
  
      def each_attribute_metadata(&block)
        @attr_md_hash.each_value(&block)
      end
  
      # @return the Attribute for the given attribute symbol or alias
      # @raise [NameError] if the attribute is not recognized
      def attribute_metadata(attribute)
        # Simple and predominant case is that attribute is a standard attribute.
        # Otherwise, resolve attribute to the standard symbol.
        attr_md = @attr_md_hash[attribute] || @attr_md_hash[standard_attribute(attribute)]
        # If not found, then delegate to handler which will either make the new
        # attribute or raise a NameError.
        attr_md || (attribute_missing(attribute) && @local_attr_md_hash[attribute])
      end
  
      # @param [Symbol, String] name_or_alias the attribute name or alias
      # @return [Symbol] the standard attribute symbol for the given name or alias
      # @raise [ArgumentError] if the attribute name or alias argument is missing
      # @raise [NameError] if the attribute is not found
      def standard_attribute(name_or_alias)
        if name_or_alias.nil? then
          raise ArgumentError.new("#{qp} standard attribute call is missing the attribute name/alias parameter")
        end
        @alias_std_attr_map[name_or_alias.to_sym] or raise NameError.new("#{self} attribute not found: #{name_or_alias}")
      end
  
      ## Metadata ATTRIBUTE FILTERS ##
  
      # @return [<Symbol>] the domain attributes which wrap a java property
      # @see Attribute#java_property?
      def java_attributes
        @java_attrs ||= attribute_filter { |attr_md| attr_md.java_property? }
      end

      alias :printable_attributes :java_attributes
  
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
  
      # @param [Boolean, nil] inc_super flag indicating whether to include dependents defined in the superclass
      # @return [<Symbol>] the dependent attributes
      def dependent_attributes(inc_super=true)
        if inc_super then
          @dep_attrs ||= attribute_filter { |attr_md| attr_md.dependent? }
        else
          @local_dep_attrs ||= dependent_attributes.compose { |attr_md| attr_md.declarer == self }
        end
      end
  
      # @return [<Symbol>] the dependent attributes
      def autogenerated_dependent_attributes
        @ag_dep_attrs ||= dependent_attributes.compose { |attr_md| attr_md.autogenerated? }
      end
  
      # @return [<Symbol>] the autogenerated logical dependent attributes
      # @see #logical_dependent_attributes
      # @see Attribute#autogenerated?
      def autogenerated_logical_dependent_attributes
        @ag_log_dep_attrs ||= dependent_attributes.compose { |attr_md| attr_md.autogenerated? and attr_md.logical? }
      end
      
      # @return [<Symbol>] the {Attribute#saved_fetch?} attributes
      def saved_fetch_attributes
        @svd_ftch_attrs ||= domain_attributes.compose { |attr_md| attr_md.saved_fetch? }
      end
      
      # @return [<Symbol>] the logical dependent attributes
      # @see Attribute#logical?
      def logical_dependent_attributes
        @log_dep_attrs ||= dependent_attributes.compose { |attr_md| attr_md.logical? }
      end
      
      # @return [<Symbol>] the unidirectional dependent attributes
      # @see Attribute#unidirectional?
      def unidirectional_dependent_attributes
        @uni_dep_attrs ||= dependent_attributes.compose { |attr_md| attr_md.unidirectional? }
      end
  
      # @return [<Symbol>] the auto-generated attributes
      # @see Attribute#autogenerated?
      def autogenerated_attributes
        @ag_attrs ||= attribute_filter { |attr_md| attr_md.autogenerated? }
      end
      
      # @return [<Symbol>] the auto-generated non-domain attributes
      # @see Attribute#nondomain?
      # @see Attribute#autogenerated?
      def autogenerated_nondomain_attributes
        @ag_nd_attrs ||= attribute_filter { |attr_md| attr_md.autogenerated? and attr_md.nondomain? }
      end
      
      # @return [<Symbol>] the {Attribute#volatile?} non-domain attributes
      def volatile_nondomain_attributes
        @unsvd_nd_attrs ||= attribute_filter { |attr_md| attr_md.volatile? and attr_md.nondomain? }
      end
  
      # @return [<Symbol>] the domain attributes which can serve as a query parameter
      # @see Attribute#searchable?
      def searchable_attributes
        @srchbl_attrs ||= attribute_filter { |attr_md| attr_md.searchable? }
      end
  
      # @return [<Symbol>] the create/update cascaded domain attributes
      # @see Attribute#cascaded?
      def cascaded_attributes
        @cscd_attrs ||= domain_attributes.compose { |attr_md| attr_md.cascaded? }
      end
  
      # @return [<Symbol>] the {#cascaded_attributes} which are saved with a proxy
      #   using the dependent saver_proxy method
      def proxied_savable_template_attributes
        @px_cscd_attrs ||= savable_template_attributes.compose { |attr_md| attr_md.proxied_save? }
      end
  
      # @return [<Symbol>] the {#cascaded_attributes} which do not have a
      #   #{Attribute#proxied_save?}
      def unproxied_savable_template_attributes
        @unpx_sv_tmpl_attrs ||= savable_template_attributes.compose { |attr_md| not attr_md.proxied_save? }
      end
  
      # @return [<Symbol>] the {#domain_attributes} to {Attribute#include_in_save_template?}
      def savable_template_attributes
        @sv_tmpl_attrs ||= domain_attributes.compose { |attr_md| attr_md.include_in_save_template? }
      end
      
      # Returns the physical or auto-generated logical dependent attributes that can
      # be copied from a save result to the given save argument object.
      #
      # @return [<Symbol>] the attributes that can be copied from a save result to a
      #  save argument object
      # @see Attribute#autogenerated?
      def copyable_saved_attributes
        @cp_sv_attrs ||= dependent_attributes.compose { |attr_md| attr_md.autogenerated? or not attr_md.logical? }
      end
  
      # Returns the subject class's required attributes, determined as follows:
      # * An attribute marked with the :mandatory flag is mandatory.
      # * An attribute marked with the :optional or :autogenerated flag is not mandatory.
      # * Otherwise, A secondary key or owner attribute is mandatory.
      def mandatory_attributes
        @mndtry_attrs ||= collect_mandatory_attributes
      end
  
      # @return [<Symbol>] the attributes which are {Attribute#creatable?}
      def creatable_attributes
        @cr_attrs ||= attribute_filter { |attr_md| attr_md.creatable? }
      end
  
      # @return [<Symbol>] the attributes which are {Attribute#updatable?}
      def updatable_attributes
        @upd_attrs ||= attribute_filter { |attr_md| attr_md.updatable? }
      end
  
      def fetched_dependent_attributes
        @ftchd_dep_attrs ||= (fetched_domain_attributes & dependent_attributes).to_a
      end
      
      def nonowner_attributes
        @nownr_atts ||= attribute_filter { |attr_md| not attr_md.owner? }
      end
      
      # @return [<Symbol>] the saved dependent attributes
      # @see Attribute#dependent?
      # @see Attribute#saved?
      def saved_dependent_attributes
        @svd_dep_attrs ||= attribute_filter { |attr_md| attr_md.dependent? and attr_md.saved? }
      end
      
      # @return [<Symbol>] the saved independent attributes
      # @see Attribute#independent?
      # @see Attribute#saved?
      def saved_independent_attributes
        @svd_ind_attrs ||= attribute_filter { |attr_md| attr_md.independent? and attr_md.saved? }
      end
  
      # @return [<Symbol>] the domain {Attribute#saved?} attributes
      def saved_domain_attributes
        @svd_dom_attrs ||= domain_attributes.compose { |attr_md| attr_md.saved? }
      end
  
      # @return [<Symbol>] the non-domain {Attribute#saved?} attributes
      def saved_nondomain_attributes
        @svd_nondom_attrs ||= nondomain_attributes.compose { |attr_md| attr_md.saved? }
      end
  
      # @return [<Symbol>] the {Attribute#volatile?} {#nondomain_attributes}
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
      #   metadata's subject class can be created
      # @see Attribute#storable_prerequisite?
      def storable_prerequisite_attributes
        @stbl_prereq_dom_attrs ||= attribute_filter { |attr_md| attr_md.storable_prerequisite? }
      end
  
      # @return [<Symbol>] the attributes which are populated from the database
      # @see Attribute#fetched?
      def fetched_attributes
        @ftchd_attrs ||= attribute_filter { |attr_md| attr_md.fetched? }
      end
  
      # Returns the domain attributes which are populated in a query on the given fetched instance of
      # this metadata's subject class. The domain attribute is fetched if it satisfies the following 
      # conditions:
      # * the attribute is a dependent attribute or of abstract domain type
      # * the attribute is not specified as unfetched in the configuration
      #
      # @return [<Symbol>] the attributes which are {Attribute#fetched?}
      def fetched_domain_attributes
        @ftchd_dom_attrs ||= domain_attributes.compose { |attr_md| attr_md.fetched? }
      end
  
      #@return [<Symbol>] the #domain_attributes which are not #fetched_domain_attributes
      def unfetched_attributes
        @unftchd_attrs ||= domain_attributes.compose { |attr_md| not attr_md.fetched? }
      end
      
      alias :toxic_attributes :unfetched_attributes
  
      # @return [<Symbol>] the Java property non-abstract {#unfetched_attributes}
      def loadable_attributes
        @ld_attrs ||= unfetched_attributes.compose { |attr_md| attr_md.java_property? and not attr_md.type.abstract? }
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
      
      # @return [{Symbol => Attribute}] the attribute => metadata hash
      def attribute_metadata_hash
        @attr_md_hash
      end
  
      # @return [{Symbol => Symbol}] the attribute alias => standard hash
      def alias_standard_attribute_hash
        @alias_std_attr_map
      end
  
      private
  
      IDENTIFIER_ATTR_ARRAY = [:identifier]
  
      # A filter on the standard attribute symbol => metadata hash that yields
      # each attribute which satisfies the attribute metadata condition.
      class Filter
        include Enumerable
  
        # @param [Class] the class whose attributes are filtered
        # @param [{Symbol => Attribute}] hash the attribute symbol => metadata hash
        # @yield [attr_md] condition which determines whether the attribute is selected
        # @yieldparam [Attribute] the metadata for the standard attribute
        # @raise [ArgumentError] if a parameter is missing 
        def initialize(klass, hash, &filter)
          raise ArgumentError.new("#{klass.qp} attribute filter missing hash argument") if hash.nil?
          raise ArgumentError.new("#{klass.qp} attribute filter missing filter block") unless block_given?
          @hash = hash
          @filter = filter
        end
  
        # @yield [attribute, attr_md] the block to apply to the filtered attribute metadata and attribute
        # @yieldparam [Symbol] attribute the attribute
        # @yieldparam [Attribute] attr_md the attribute metadata
        def each_pair
          @hash.each { |attr, attr_md| yield(attr, attr_md) if @filter.call(attr_md) }
        end
        
        # @return [<(Symbol, Attribute)>] the (symbol, attribute) enumerator
        def enum_pairs
          enum_for(:each_pair)
        end
        
        # @yield [attribute] block to apply to each filtered attribute
        # @yieldparam [Symbol] the attribute which satisfies the filter condition
        def each_attribute(&block)
          each_pair { |attr, attr_md| yield(attr) }
        end
        
        alias :each :each_attribute
  
        # @yield [attr_md] the block to apply to the filtered attribute metadata
        # @yieldparam [Attribute] attr_md the attribute metadata
        def each_metadata
          each_pair { |attr, attr_md| yield(attr_md) }
        end
        
        # @return [<Attribute>] the attribute metadata enumerator
        def enum_metadata
          enum_for(:each_metadata)
        end
        
        # @yield [attribute] the block to apply to the attribute
        # @yieldparam [Symbol] attribute the attribute
        # @return [Attribute] the first attribute metadata satisfies the block
        def detect_metadata
          each_pair { |attr, attr_md| return attr_md if yield(attr) }
          nil
        end
        
        # @yield [attr_md] the block to apply to the attribute metadata
        # @yieldparam [Attribute] attr_md the attribute metadata
        # @return [Symbol] the first attribute whose metadata satisfies the block
        def detect_with_metadata
          each_pair { |attr, attr_md| return attr if yield(attr_md) }
          nil
        end
  
        # @yield [attr_md] the attribute selection filter
        # @yieldparam [Attribute] attr_md the candidate attribute metadata
        # @return [Filter] a new Filter which applies the filter block given to this
        #   method with the Attribute enumerated by this filter
        def compose
          Filter.new(self, @hash) { |attr_md| @filter.call(attr_md) and yield(attr_md) }
        end
      end
      
      # Returns the most specific attribute which references the given target type, or nil if none.
      # If the given class can be returned by more than on of the attributes, then the attribute
      # is chosen whose return type most closely matches the given class.
      #
      # @param [Class] klass the target type
      # @param [Filter, nil] attributes the attributes to check (default all domain attributes)
      # @return [Symbol, nil] the most specific reference attribute, or nil if none
      def most_specific_domain_attribute(klass, attributes=nil)
        attributes ||= domain_attributes
        candidates = attributes.enum_metadata
        best = candidates.inject(nil) do |better, attr_md|
          # If the attribute can return the klass then the return type is a candidate.
          # In that case, the klass replaces the best candidate if it is more specific than
          # the best candidate so far.
          klass <= attr_md.type ? (better && better.type <= attr_md.type ? better : attr_md) : better
        end
        if best then
          logger.debug { "Most specific #{qp} -> #{klass.qp} reference from among #{candidates.qp} is #{best.declarer.qp}.#{best}." }
          best.to_sym
        end
      end
      
      # Returns an Enumerable on this Resource class's attributes which iterates on each attribute whose
      # corresponding Attribute satisfies the given filter block.
      #
      # @yield [attr_md] the attribute selector
      # @yieldparam [Attribute] attr_md the candidate attribute
      # @return [Filter] an {Attribute} enumerator
      def attribute_filter(&filter)
        # initialize the attributes on demand
        unless introspected? then introspect end
        # make the attribute filter
        Filter.new(self, @attr_md_hash, &filter)
      end
  
      # Initializes the attribute meta-data structures.
      def init_attributes
        @local_std_attr_hash = {}
        @alias_std_attr_map = append_ancestor_enum(@local_std_attr_hash) { |par| par.alias_standard_attribute_hash }
        @local_attr_md_hash = {}
        @attr_md_hash = append_ancestor_enum(@local_attr_md_hash) { |par| par.attribute_metadata_hash }
        @attributes = Enumerable::Enumerator.new(@attr_md_hash, :each_key)
        @local_mndty_attrs = Set.new
        @local_defaults = {}
        @defaults = append_ancestor_enum(@local_defaults) { |par| par.defaults }
      end
      
      # Detects the first attribute with the given type.
      #
      # @param [Class] klass the target attribute type
      # @return [Symbol, nil] the attribute with the given type
      def detect_attribute_with_type(klass)
        attribute_metadata_hash.detect_key_with_value { |attr_md| attr_md.type == klass }
      end
      
      # Creates the given attribute alias. If the attribute metadata is registered with this class, then
      # this method overrides {Class#alias_attribute} to create a new alias reader (writer) method
      # which delegates to the attribute reader (writer, resp.). This aliasing mechanism differs from
      # {Class#alias_attribute}, which directly aliases the existing reader or writer method.
      # Delegation allows the alias to pick up run-time redefinitions of the aliased reader and writer.
      # If the attribute metadata is not registered with this class, then this method delegates to
      # {Class#alias_attribute}.
      #
      # @param [Symbol] aliaz the attribute alias
      # @param [Symbol] attribute the attribute to alias
      def alias_attribute(aliaz, attribute)
        if attribute_defined?(attribute) then
          add_attribute_aliases(aliaz => attribute)
        else
          super
        end
      end
  
      # Creates the given aliases to attributes.
      #
      # @param [{Symbol => Symbol}] hash the alias => attribute hash
      # @see #attribute_alias
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
        # If this class is the declarer, then simply set the attribute type.
        # Otherwise, if the attribute type is unspecified or is a superclass of the given class,
        # then make a new attribute metadata for this class.
        if attr_md.declarer == self then
          logger.debug { "Set #{qp}.#{attribute} type to #{klass.qp}." }
          attr_md.type = klass
        elsif attr_md.type.nil? or klass < attr_md.type then
          new_attr_md = attr_md.restrict(self, :type => klass)
          logger.debug { "Restricted #{attr_md.declarer.qp}.#{attribute}(#{attr_md.type.qp}) to #{qp} with return type #{klass.qp}." }
          add_attribute_metadata(new_attr_md)
        elsif klass != attr_md.type then
          raise ArgumentError.new("Cannot reset #{qp}.#{attribute} type #{attr_md.type} to incompatible #{klass.qp}")
        end
      end
  
      def add_attribute_defaults(hash)
        hash.each { |attr, value| @local_defaults[standard_attribute(attr)] = value }
      end
  
      def add_mandatory_attributes(*attributes)
        attributes.each { |attr| @local_mndty_attrs << standard_attribute(attr) }
      end
  
      # Marks the given attribute with flags supported by {Attribute#qualify}.
      def qualify_attribute(attribute, *flags)
        attr_md = attribute_metadata(attribute)
        if attr_md.declarer == self then
          attr_md.qualify(*flags)
        else
          logger.debug { "Restricting #{attr_md.declarer.qp}.#{attribute} to #{qp} with additional flags #{flags.to_series}" }
          new_attr_md = attr_md.restrict_flags(self, *flags)
          add_attribute_metadata(new_attr_md)
        end
      end
  
      # Removes the given attribute from this Resource.
      # An attribute declared in a superclass Resource is hidden from this Resource but retained in
      # the declaring Resource.
      def remove_attribute(attribute)
        std_attr = standard_attribute(attribute)
        # if the attribute is local, then delete it, otherwise filter out the superclass attribute
        attr_md = @local_attr_md_hash.delete(std_attr)
        if attr_md then
          # clear the inverse, if any
          attr_md.inverse = nil
          # remove from the mandatory attributes, if necessary
          @local_mndty_attrs.delete(std_attr)
          # remove from the attribute => metadata hash
          @local_std_attr_hash.delete_if { |aliaz, attr| attr == std_attr }
        else
          # Filter the superclass hashes.
          anc_md_hash = @attr_md_hash.components[1]
          @attr_md_hash.components[1] = anc_md_hash.filter_on_key { |attr| attr != attribute }
          anc_alias_hash = @alias_std_attr_map.components[1]
          @alias_std_attr_map.components[1] = anc_alias_hash.filter_on_key { |attr| attr != attribute }
        end
      end
  
      def add_attribute_metadata(attr_md)
        attr = attr_md.to_sym
        @local_attr_md_hash[attr] = attr_md
        # map the attribute symbol to itself in the alias map
        @local_std_attr_hash[attr] = attr
      end
  
      # Records that the given aliaz aliases a standard attribute.
      def add_alias(aliaz, attribute)
        std_attr = standard_attribute(attribute)
        raise ArgumentError.new("#{self} attribute not found: #{attribute}") if std_attr.nil?
        @local_std_attr_hash[aliaz.to_sym] = std_attr
      end
  
      # Appends to the given enumerable the result of evaluating the block given to this method
      # on the superclass, if the superclass is in the same parent module as this class.
      #
      # @param [Enumerable] enum the base collection
      # @return [Enumerable] the {Enumerable#union} of the base collection with the superclass
      #   collection, if applicable 
      def append_ancestor_enum(enum)
        return enum unless superclass.parent_module == parent_module
        anc_enum = yield superclass
        if anc_enum.nil? then raise MetadataError.new("#{qp} superclass #{superclass.qp} does not have required metadata") end
        enum.union(anc_enum)
      end
  
      # Collects the {Attribute#fetched_dependent?} and {Attribute#fetched_independent?}
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
        oattr = mandatory_owner_attribute
        mandatory << oattr if oattr
        # remove autogenerated or optional attributes
        mandatory.delete_if { |attr| attribute_metadata(attr).autogenerated? or attribute_metadata(attr).optional? }
        @local_mndty_attrs.merge!(mandatory)
        append_ancestor_enum(@local_mndty_attrs) { |par| par.mandatory_attributes }
      end
      
      # @return [Symbol, nil] the unique non-self-referential owner attribute, if one exists
      def mandatory_owner_attribute
        attr = owner_attribute || return
        attr_md = attribute_metadata(attr)
        attr if attr_md.java_property? and attr_md.type != self
      end
  
      # Raises a NameError. Domain classes can override this method to dynamically create a new reference attribute.
      #
      # @raise [NameError] always
      def attribute_missing(attribute)
        raise NameError.new("#{name.demodulize} attribute not found: #{attribute}")
      end
    end
  end
end