require 'forwardable'
require 'caruby/util/inflector'
require 'caruby/util/log'
require 'caruby/util/pretty_print'
require 'caruby/util/validation'
require 'caruby/util/collection'
require 'caruby/domain/merge'
require 'caruby/domain/reference_visitor'
require 'caruby/database/persistable'
require 'caruby/domain/inversible'
require 'caruby/domain/resource_metadata'
require 'caruby/domain/resource_module'
require 'caruby/migration/migratable'

module CaRuby
  # The Domain module is included by Java domain classes.
  # This module defines essential common domain methods that enable the jRuby-Java API bridge.
  # Classes which include Domain must implement the +metadata+ Domain::Metadata accessor method.
  module Resource
    include Mergeable, Migratable, Persistable, Inversible, Validation

    # Sets the default attribute values for this domain object and its dependents. If this Resource
    # does not have an identifier, then missing attributes are set to the values defined by
    # {ResourceAttributes#add_attribute_defaults}.
    #
    # _Implementation Note_: subclasses should override the private {#add_defaults_local} method
    # rather than this method.
    #
    # @return [Resource] self
    def add_defaults
      # apply owner defaults
      if owner and owner.identifier.nil? then
        owner.add_defaults
      else
        logger.debug { "Adding defaults to #{qp} and its dependents..." }
        # apply the local and dependent defaults
        add_defaults_recursive
      end
      self
    end

    # Validates this domain object and its cascaded dependents for completeness prior to a
    # database create or update operation.
    # The object is valid if it contains a non-nil value for each mandatory property.
    # Objects which have already been validated are skipped.
    # Returns this domain object.
    #
    # @raise [ValidationError] if a mandatory attribute value is missing
    def validate
      unless @validated then
        logger.debug { "Validating #{qp} required attributes #{self.mandatory_attributes.to_a.to_series}..." }
        invalid = missing_mandatory_attributes
        unless invalid.empty? then
          logger.error("Validation of #{qp} unsuccessful - missing #{invalid.join(', ')}:\n#{dump}")
          raise ValidationError.new("Required attribute value missing for #{self}: #{invalid.join(', ')}")
        end
      end
      self.class.cascaded_attributes.each do |attr|
        send(attr).enumerate { |dep| dep.validate }
      end
      @validated = true
      self
    end
    
    # @return [Boolean] whether this domain object has {#searchable_attributes}
    def searchable?
      not searchable_attributes.nil?
    end

    # Returns the attributes to use for a search using this domain object as a template, determined
    # as follows:
    # * If this domain object has a non-nil primary key, then the primary key is the search criterion.
    # * Otherwise, if this domain object has a secondary key and each key attribute value is not nil,
    #   then the secondary key is the search criterion.
    # * Otherwise, if this domain object has an alternate key and each key attribute value is not nil,
    #   then the aklternate key is the search criterion.
    #
    # @return [<Symbol>] the attributes to use for a search on this domain object
    def searchable_attributes
      key_attrs = self.class.primary_key_attributes
      return key_attrs if key_searchable?(key_attrs)
      key_attrs = self.class.secondary_key_attributes
      return key_attrs if key_searchable?(key_attrs)
      key_attrs = self.class.alternate_key_attributes
      return key_attrs if key_searchable?(key_attrs)
    end

    # Returns a new domain object with the given attributes copied from this domain object. The attributes
    # argument consists of either attribute Symbols or a single Enumerable consisting of Symbols.
    # The default attributes are the {ResourceAttributes#nondomain_attributes}.
    #
    # @param [<Symbol>] attributes the attributes to copy
    # @return [Resource] a copy of this domain object
    def copy(*attributes)
      if attributes.empty? then
        attributes = self.class.nondomain_attributes
      elsif Enumerable === attributes.first then
        raise ArgumentError.new("#{qp} copy attributes argument is not a Symbol: #{attributes.first}") unless attributes.size == 1
        attributes = attributes.first
      end
      self.class.new.merge_attributes(self, attributes)
    end

    # Clears the given attribute value. If the current value responds to the +clear+ method,
    # then the current value is cleared. Otherwise, the value is set to {ResourceMetadata#empty_value}.
    #
    # @param [Symbol] attribute the attribute to clear
    def clear_attribute(attribute)
      # the current value to clear
      current = send(attribute)
      return if current.nil?
      # call the current value clear if possible.
      # otherwise, set the attribute to the empty value.
      if current.respond_to?(:clear) then
        current.clear
      else
        writer = self.class.attribute_metadata(attribute).writer
        value = self.class.empty_value(attribute)
        send(writer, value)
      end
    end

    # Sets this domain object's attribute to the value. This method clears the current attribute value,
    # if any, and merges the new value. Merge rather than assignment ensures that a collection type
    # is preserved, e.g. an Array value is assigned to a set domain type by first clearing the set
    # and then merging the array content into the set.
    #
    # @see Mergeable#merge_attribute
    def set_attribute(attribute, value)
      # bail out if the value argument is the current value
      return value if value.equal?(send(attribute))
      clear_attribute(attribute)
      merge_attribute(attribute, value)
    end

    # Returns the secondary key attribute values as follows:
    # * If there is no secondary key, then this method returns nil.
    # * Otherwise, if the secondary key attributes is a singleton Array, then the key is the
    #   value of the sole key attribute.
    # * Otherwise, the key is an Array of the key attribute values.
    #
    # @return [Array, Object] the key attribute values
    def key
      attrs = self.class.secondary_key_attributes
      case attrs.size
        when 0 then nil
        when 1 then send(attrs.first)
        else attrs.map { |attr| send(attr) }
      end
    end

    # @return [Resource, nil] the domain object that owns this object, or nil if this object
    #   is not dependent on an owner
    def owner
      self.class.owner_attributes.detect_value { |attr| send(attr) }
    end
    
    # Sets this dependent's owner attribute to the given domain object.
    #
    # @param [Resource] owner the owner domain object
    # @raise [NoMethodError] if this Resource's class does not have exactly one owner attribute
    def owner=(owner)
      attr = self.class.owner_attribute
      if attr.nil? then raise NoMethodError.new("#{self.class.qp} does not have a unique owner attribute") end
      set_attribute(attr, owner)
    end

    # @param [Resource] other the domain object to check
    # @return [Boolean] whether the other domain object is this object's {#owner} or an
    #  {#owner_ancestor?} of this object's {#owner}
    def owner_ancestor?(other)
      owner = self.owner
      owner and (owner == other or owner.owner_ancestor?(other))
    end

    # Returns an attribute => value hash for the specified attributes with a non-nil, non-empty value.
    # The default attributes are this domain object's class {ResourceAttributes#attributes}.
    # Only non-nil attributes defined by this Resource are included in the result hash.
    #
    # @param [<Symbol>, nil] attributes the attributes to merge
    # @return [{Symbol => Object}] the attribute => value hash
    def value_hash(attributes=nil)
      attributes ||= self.class.attributes
      attributes.to_compact_hash { |attr| send(attr) if self.class.method_defined?(attr) }
    end

    # Returns the domain object references for the given attributes.
    #
    # @param [<Symbol>, nil] the domain attributes to include, or nil to include all domain attributes
    # @return [<Resource>] the referenced attribute domain object values
    def references(attributes=nil)
      attributes ||= self.class.domain_attributes
      attributes.map { |attr| send(attr) }.flatten.compact
    end

    # @return [Boolean] whether this domain object is dependent on another entity
    def dependent?
      self.class.dependent?
    end

    # @return [Boolean] whether this domain object is not dependent on another entity
    def independent?
      not dependent?
    end

    # Enumerates over this domain object's dependents.
    #
    # @yield [dep] the block to execute on the dependent
    # @yieldparam [Resource] dep the dependent
    def each_dependent
      self.class.dependent_attributes.each do |attr|
       send(attr).enumerate { |dep| yield dep }
      end
    end
    
    # @return [Enumerable] this domain object's dependents
    def dependents
      enum_for(:each_dependent)
    end
    
    # Returns the attributes which are required for save. This base implementation returns the
    # class {ResourceAttributes#mandatory_attributes}. Subclasses can override this method
    # for domain object state-specific refinements.
    #
    # @return [<Symbol>] the required attributes for a save operation
    def mandatory_attributes
      self.class.mandatory_attributes
    end

    # Returns the attribute references which directly depend on this owner.
    # The default is the attribute value.
    #
    # Returns an Enumerable. If the value is not already an Enumerable, then this method
    # returns an empty array if value is nil, or a singelton array with value otherwise.
    #
    # If there is more than one owner of a dependent, then subclasses should override this
    # method to select dependents whose dependency path is shorter than an alternative
    # dependency path, e.g. in caTissue a Specimen is owned by both a SCG and a parent
    # Specimen. In that case, the SCG direct dependents consist of top-level Specimens
    # owned by the SCG but not derived from another Specimen.
    #
    # @param [Symbol] attribute the dependent attribute
    # @return [<Resource>] the attribute value, wrapped in an array if necessary
    def direct_dependents(attribute)
      deps = send(attribute)
      case deps
        when Enumerable then deps
        when nil then Array::EMPTY_ARRAY
        else [deps]
      end
    end

    # @param [Resource] the domain object to match
    # @return [Boolean] whether this object matches the fetched other object on class
    #   and key values
    def match?(other)
      match_in([other])
    end

    # Matches this dependent domain object with the others on type and key attributes
    # in the scope of a parent object.
    # Returns the object in others which matches this domain object, or nil if none.
    #
    # The match attributes are, in order:
    # * the primary key
    # * the secondary key
    # * the alternate key
    #
    # This domain object is matched against the others on the above attributes in succession
    # until a unique match is found. The key attribute matches are strict, i.e. each
    # key attribute value must be non-nil and match the other value.
    #
    # @param [<Resource>] the candidate domain object matches
    # @return [Resource, nil] the matching domain object, or nil if no match
    def match_in(others)
      # trivial case: self is in others
      return self if others.include?(self)
      # filter for the same type
      others = others.filter { |other| self.class === other }
      # match on primary, secondary or alternate key
      match_unique_object_with_attributes(others, self.class.primary_key_attributes) or
      match_unique_object_with_attributes(others, self.class.secondary_key_attributes) or
      match_unique_object_with_attributes(others, self.class.alternate_key_attributes)
    end

    # Returns the match of this domain object in the scope of a matching owner as follows:
    # * If {#match_in} returns a match, then that match is the result is used.
    # * Otherwise, if this is a dependent attribute then the match is attempted on a
    #   secondary key without owner attributes. Defaults are added to this object in order
    #   to pick up potential secondary key values.
    #
    # @param (see #match_in)
    # @return (see #match_in)
    def match_in_owner_scope(others)
      match_in(others) or others.detect { |other| match_without_owner_attribute?(other) }
    end

    # @return [{Resouce => Resource}] a source => target hash of the given sources which match
    #   the targets using the {#match_in} method
    def self.match_all(sources, targets)
      DEF_MATCHER.match(sources, targets)
    end

    # Returns the difference between this Persistable and the other Persistable for the
    # given attributes. The default attributes are the {ResourceAttributes#nondomain_attributes}.
    #
    # @param [Resource] other the domain object to compare
    # @param [<Symbol>, nil] attributes the attributes to compare
    # @return (see Hashable#diff)
    def diff(other, attributes=nil)
      attributes ||= self.class.nondomain_attributes
      vh = value_hash(attributes)
      ovh = other.value_hash(attributes)
      vh.diff(ovh) { |key, v1, v2| Resource.value_equal?(v1, v2) }
    end

    # Returns the domain object in others which matches this dependent domain object
    # within the scope of a parent on a minimally acceptable constraint. This method
    # is used when this object might be partially complete--say, lacking a secondary key
    # value--but is expected to match one of the others, e.g. when matching a referenced
    # object to its fetched counterpart.
    #
    # This base implementation returns whether the following conditions hold:
    # 1. other is the same class as this domain object
    # 2. if both identifiers are non-nil, then they are equal
    #
    # Subclasses can override this method to impose additional minimal consistency constraints.
    #
    # @param [Resource] other the domain object to match against
    # @return [Boolean] whether this Resource equals other
    def minimal_match?(other)
      self.class === other and
      (identifier.nil? or other.identifier.nil? or identifier == other.identifier)
    end

    # Returns an enumerator on the transitive closure of the reference attributes.
    # If a block is given to this method, then the block called on each reference determines
    # which attributes to visit. Otherwise, all saved references are visited.
    #
    # @yield [ref] reference visit attribute selector
    # @yieldparam [Resource] ref the domain object to visit
    # @return [Enumerable] the reference transitive closure
    def reference_hierarchy
      ReferenceVisitor.new { |ref| yield ref }.to_enum(self)
    end

    # Returns the value for the given attribute path Array or String expression, e.g.:
    #   study.path_value("site.address.state")
    # follows the +study+ -> +site+ -> +address+ -> +state+ accessors and returns the +state+
    # value, or nil if any intermediate reference is nil.
    # The array form for the above example is:
    #  study.path_value([:site, :address, :state])
    #
    # @param [<Symbol>] path the attributes to navigate
    # @return the attribute navigation result
    def path_value(path)
      path = path.split('.').map { |attr| attr.to_sym } if String === path
      path.inject(self) do |parent, attr|
        value = parent.send(attr)
        return if value.nil?
        value
      end
    end

    # Applies the operator block to this object and each domain object in the reference path.
    # This method visits the transitive closure of each recursive path attribute.
    #
    # For example, given the attributes:
    #   treatment: BioMaterial -> Treatment
    #   measurement: Treatment -> BioMaterial
    # and +BioMaterial+ instance +biospecimen+, then:
    #   biospecimen.visit_path[:treatment, :measurement, :biomaterial]
    # visits +biospecimen+ and all biomaterial, treatments and measurements derived
    # directly or indirectly from +biospecimen+.
    #
    # @param [<Symbol>] path the attributes to visit
    # @yieldparam [Symbol] attribute the attribute to visit
    # @return the visit result
    def visit_path(path, &operator)
      visitor = ReferencePathVisitorFactory.create(self.class, path)
      visitor.visit(self, &operator)
    end

    # Applies the operator block to the transitive closure of this domain object's dependency relation.
    # The block argument is a dependent.
    #
    # @yield [dep] operation on the visited domain object
    # @yieldparam [Resource] dep the domain object to visit 
    def visit_dependents(&operator) # :yields: dependent
      DEPENDENT_VISITOR.visit(self, &operator)
    end

    # Applies the operator block to the transitive closure of this domain object's owner relation.
    #
    # @yield [dep] operation on the visited domain object
    # @yieldparam [Resource] dep the domain object to visit 
    def visit_owners(&operator) # :yields: owner
      ref = owner
      yield(ref) and ref.visit_owners(&operator) if ref
    end

    # @param q the PrettyPrint queue 
    # @return [String] the formatted content of this Resource
    def pretty_print(q)
      q.text(qp)
      content = printable_content
      q.pp_hash(content) unless content.empty?
    end

    # Prints this domain object's content and recursively prints the referenced content.
    # The optional selector block determines the attributes to print. The default is the
    # {ResourceAttributes#java_attributes}. The database lazy loader is disabled during
    # the execution of this method. Thus, the printed content reflects the transient
    # in-memory object graph rather than the persistent content.
    #
    # @yield [owner] the owner attribute selector
    # @yieldparam [Resource] owner the domain object to print
    # @return [String] the domain object content
    def dump(&selector)
      database.lazy_loader.disable { DetailPrinter.new(self, &selector).pp_s }
    end

    # Prints this domain object in the format:
    #   class_name@object_id{attribute => value ...}
    # The default attributes include identifying attributes.
    #
    # @param [<Symbol>] attributes the attributes to print
    # @return [String] the formatted content
    def to_s(attributes=nil)
      content = printable_content(attributes)
      content_s = content.pp_s(:single_line) unless content.empty?
      "#{print_class_and_id}#{content_s}"
    end

    alias :inspect :to_s

    # Returns this domain object's attributes content as an attribute => value hash
    # suitable for printing.
    #
    # The default attributes are this object's saved attributes. The optional
    # reference_printer is used to print a referenced domain object.
    #
    # @param [<Symbol>, nil] attributes the attributes to print
    # @yield [ref] the reference print formatter 
    # @yieldparam [Rresource] ref the referenced domain object to print
    # @return [{Symbol => String}] the attribute => content hash
    def printable_content(attributes=nil, &reference_printer) # :yields: reference
      attributes ||= printworthy_attributes
      vh = value_hash(attributes)
      vh.transform { |value| printable_value(value, &reference_printer) }
    end

    # Returns whether value equals other modulo the given matches according to the following tests:
    # * _value_ == _other_
    # * _value_ and _other_ are Resource instances and _value_ is a {#match?} with _other_.
    # * _value_ and _other_ are Enumerable with members equal according to the above conditions.
    # * _value_ and _other_ are DateTime instances and are equal to within one second.
    #
    # The DateTime comparison accounts for differences in the Ruby -> Java -> Ruby roundtrip
    # of a date attribute, which loses the seconds fraction.
    #
    # @return whether value and other are equal according to the above tests
    def self.value_equal?(value, other, matches=nil)
      if value == other then
        true
      elsif value.collection? and other.collection? then
        collection_value_equal?(value, other, matches)
      elsif DateTime === value and DateTime === other then
        (value - other).abs.floor.zero?
      elsif Resource === value and value.class === other then
        value.match?(other)
      elsif matches then
        matches[value] == other
      else
        false
      end
    end
    
    protected

    # Adds the default values to this object, if it is not already fetched, and its dependents.
    def add_defaults_recursive
      # add the local defaults unless there is an identifier
      add_defaults_local
      # add dependent defaults
      each_defaults_dependent { |dep| dep.add_defaults_recursive }
    end

    # Returns the required attributes for this domain object which are nil or empty.
    #
    # This method is in protected scope to allow the +CaTissue+ domain module to
    # work around a caTissue bug (see that module for details). Other definitions
    # of this method are discouraged.
    def missing_mandatory_attributes
      mandatory_attributes.select { |attr| send(attr).nil_or_empty? }
    end

    private

    # The copy merge call options.
    COPY_MERGE_OPTS = {:inverse => false}

    # The dependent attribute visitor.
    #
    # @see #visit_dependents
    DEPENDENT_VISITOR = CaRuby::ReferenceVisitor.new { |obj| obj.class.dependent_attributes }

    # Matches the given targets to sources using {Resource#match_in}.
    class Matcher
      def match(sources, targets)
        unmatched = Set === sources ? sources.dup : sources.to_set
        matches = {}
        targets.each do |tgt|
          src = tgt.match_in(unmatched)
          if src then
            unmatched.delete(src)
            matches[src] = tgt
          end
        end
        matches
      end
    end

    DEF_MATCHER = Matcher.new

    # Sets the default attribute values for this domain object. Unlike {#add_defaults}, this
    # method does not set defaults for dependents. This method sets the configuration values
    # for this domain object as described in {#add_defaults}, but does not set defaults for
    # dependents.
    #
    # This method is the integration point for subclasses to augment defaults with programmatic logic.
    # If a subclass overrides this method, then it should call super before setting the local
    # default attributes. This ensures that configuration defaults takes precedence.
    def add_defaults_local
      logger.debug { "Adding defaults to #{qp}..." }
      merge_attributes(self.class.defaults)
    end
    
    # Enumerates the dependents for setting defaults. Subclasses can override if the
    # dependents must be visited in a certain order.
    alias :each_defaults_dependent :each_dependent

    # @return [Boolean] whether the given key attributes is non-empty and each attribute in the key has a non-nil value
    def key_searchable?(attributes)
      not (attributes.empty? or attributes.any? { |attr| send(attr).nil? })
    end

    def self.collection_value_equal?(value, other, matches=nil)
      value.size == other.size and value.all? { |v| other.include?(v) or (matches and other.include?(matches[v])) }
    end

    # A DetailPrinter formats a domain object value for printing using {#to_s} the first time the object
    # is encountered and a ReferencePrinter on the object subsequently.
    class DetailPrinter
      alias :to_s :pp_s

      alias :inspect :to_s

      # Creates a DetailPrinter on the base object.
      def initialize(base, visited=Set.new, &selector)
        @base = base
        @visited = visited << base
        @selector = selector || Proc.new { |ref| ref.class.java_attributes }
      end

      def pretty_print(q)
        q.text(@base.qp)
        # pretty-print the standard attribute values
        attrs = @selector.call(@base)
        content = @base.printable_content(attrs) do |ref|
          @visited.include?(ref) ? ReferencePrinter.new(ref) : DetailPrinter.new(ref, @visited) { |ref| @selector.call(ref) }
        end
        q.pp_hash(content)
      end
    end

    # A ReferencePrinter formats a reference domain object value for printing with just the class and Ruby object_id.
    class ReferencePrinter
      extend Forwardable

      def_delegator(:@base, :qp, :to_s)

      alias :inspect :to_s

      # Creates a ReferencePrinter on the base object.
      def initialize(base)
        @base = base
      end
    end

    # Returns a value suitable for printing. If value is a domain object, then the block provided to this method is called.
    # The default block creates a new ReferencePrinter on the value.
    def printable_value(value, &reference_printer)
      Collector.on(value) do |item|
        if Resource === item then
          block_given? ? yield(item) : printable_value(item) { |ref| ReferencePrinter.new(ref) }
        else
          item
        end
      end
    end

    # Returns an attribute => value hash for the +identifier+ attribute, if there is a non_nil +identifier+,
    # If +identifier+ is nil, then this method returns the secondary key attributes, if they exist,
    # or the mergeable attributes otherwise. If this is a dependent object, then the owner attribute is
    # removed from the returned array.
    def printworthy_attributes
      return self.class.primary_key_attributes if identifier
      attrs = self.class.secondary_key_attributes
      attrs = self.class.nondomain_java_attributes if attrs.empty?
      attrs = self.class.fetched_attributes if attrs.empty?
      attrs
    end

    # Substitutes attribute with the standard attribute and a Java non-Domain instance value with a Domain object if necessary.
    #
    # Returns the [standard attribute, standard value] array.
    def standardize_attribute_value(attribute, value)
      attr_md = self.class.attribute_metadata(attribute)
      if attr_md.nil? then
        raise ArgumentError.new("#{attribute} is neither a #{self.class.qp} standard attribute nor an alias for a standard attribute")
      end
      # standardize the value if necessary
      std_val = attr_md.type && attr_md.type < Resource ? standardize_domain_value(value) : value
      [attr_md.to_sym, std_val]
    end

    # Returns a Domain object for a Java non-Domain instance value.
    def standardize_domain_value(value)
      if value.nil? or Resource === value then
         value
      elsif Enumerable === value then
        # value is a collection; if value is a nested collection (highly unlikely), then recursively standarize
        # the value collection members. otherwise, leave the value alone.
        value.empty? || Resource === value.first ? value : value.map { |item| standardize_domain_value(item) }
      else
        # return a new Domain object built from the source Java domain object
        # (unlikely unless value is a weird toxic Hibernate proxy)
        logger.debug { "Creating standard domain object from #{value}..." }
        Domain.const_get(value.class.qp).new.merge_attributes(value)
      end
    end

    # Returns whether the other domain object matches this domain object on a secondary
    # key without owner attributes. Defaults are added to this object in order to pick up
    # potential secondary key values.
    # 
    # @param (see #match_in)
    # @return [Boolean] whether the other domain object matches this domain object on a
    #   secondary key without owner attributes
    def match_without_owner_attribute?(other)
      oattrs = self.class.owner_attributes
      return if oattrs.empty?
      # match on the secondary key
      self.class.secondary_key_attributes.all? do |attr|
        oattrs.include?(attr) or matches_attribute_value?(other, attr, send(attr))
      end
    end

    def delegate_to_inverse_setter(attr_md, ref, writer)
      logger.debug { "Setting #{qp} #{attr_md} by setting the #{ref.qp} inverse attribute #{attr_md.inverse}..." }
      ref.send(writer, self)
    end

    # Returns 0 if attribute is a Java primitive number,
    # +false+ if attribute is a Java primitive boolean,
    # an empty collectin if the Java property is a collection,
    # nil otherwise.
    def empty_value(attribute)
      type = java_type(attribute) || return
      if type.primitive? then
        type.name == 'boolean' ? false : 0
      else
        self.class.empty_value(attribute)
      end
    end

    # Returns the Java type of the given attribute, or nil if attribute is not a Java property attribute.
    def java_type(attribute)
      attr_md = self.class.attribute_metadata(attribute)
      attr_md.property_descriptor.property_type if JavaAttributeMetadata === attr_md
    end

    # Returns the source => target hash of matches for the given attr_md newval sources and
    # oldval targets. If the matcher block is given, then that block is called on the sources
    # and targets. Otherwise, {Resource.match_all} is called.
    #
    # @param [AttributeMetadata] attr_md the attribute to match
    # @param newval the source value
    # @param oldval the target value
    # @yield [sources, targets] matches sources to targets
    # @yieldparam [<Resource>] sources an Enumerable on the source value
    # @yieldparam [<Resource>] targets an Enumerable on the target value
    # @return [{Resource => Resource}] the source => target matches
    def match_attribute_value(attr_md, newval, oldval)
      # make Enumerable targets and sources for matching
      sources = newval.to_enum
      targets = oldval.to_enum
      
      # match sources to targets
      logger.debug { "Matching source #{newval.qp} to target #{qp} #{attr_md} #{oldval.qp}..." } unless oldval.nil_or_empty?
      matches = block_given? ? yield(sources, targets) : Resource.match_all(sources, targets)
      logger.debug { "Matched #{qp} #{attr_md}: #{matches.qp}." } unless matches.empty?
      matches
    end
    
    # Returns the object in others which uniquely matches this domain object on the given attributes,
    # or nil if there is no unique match. This method returns nil if any attributes value is nil.
    def match_unique_object_with_attributes(others, attributes)
      vh = value_hash(attributes)
      return if vh.empty? or vh.size < attributes.size
      matches = match_attribute_values(others, vh)
      matches.first if matches.size == 1
    end

    # Returns the domain objects in others whose class is the same as this object's class
    # and whose attribute values equal those in the given attr_value_hash.
    def match_attribute_values(others, attr_value_hash)
      others.select do |other|
        self.class === other and attr_value_hash.all? do |attr, value|
          matches_attribute_value?(other, attr, value)
        end
      end
    end

    # Returns whether this Resource's attribute value matches the fetched other attribute.
    # A domain attribute match is determined by {#match?}.
    # A non-domain attribute match is determined by an equality comparison.
    def matches_attribute_value?(other, attribute, value)
      other_val = other.send(attribute)
      if Resource === value then
        value.match?(other_val)
      else
        value == other_val
      end
    end

    # Returns the attribute => value hash to use for matching this domain object as follows:
    # * If this domain object has a database identifier, then the identifier is the sole match criterion attribute.
    # * Otherwise, if a secondary key is defined for the object's class, then those attributes are used.
    # * Otherwise, all attributes are used.
    #
    # If any secondary key value is nil, then this method returns an empty hash, since the search is ambiguous.
    def search_attribute_values
      # if this object has a database identifier, then the identifier is the search criterion
      identifier.nil? ? non_id_search_attribute_values : { :identifier => identifier }
    end

    # Returns the attribute => value hash to use for matching this domain object.
    # @see #search_attribute_values the method specification
    def non_id_search_attribute_values
      # if there is a secondary key, then search on those attributes.
      # otherwise, search on all attributes.
      key_attrs = self.class.secondary_key_attributes
      attrs = key_attrs.empty? ? self.class.nondomain_java_attributes : key_attrs
      # associate the values
      attr_values = attrs.to_compact_hash { |attr| send(attr) }
      # if there is no secondary key, then cull empty values
      key_attrs.empty? ? attr_values.delete_if { |attr, value| value.nil? } : attr_values
    end
  end
end