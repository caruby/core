require 'jinx/resource/reference_visitor'
require 'caruby/database/persistable'
require 'caruby/database/lazy_loader'

module CaRuby
  class Database
    # @return [LazyLoader] this database's lazy loader
    attr_reader :lazy_loader
    
    # Database {Persistable} mediator.
    # A module which includes {Persistifier} must implement the {Reader#fetch_association} method.
    module Persistifier
      # Adds query capability to this Database.
      def initialize
        super
        @ftchd_vstr = Jinx::ReferenceVisitor.new { |ref| ref.class.fetched_domain_attributes }
        # the demand loader
        @lazy_loader = LazyLoader.new { |obj, pa| lazy_load(obj, pa) }
      end
    
      # Clears the cache.
      def clear
        @cache.clear if @cache
      end
      
      private

      # Adds this database's lazy loader to the given domain object.
      #
      # @param [Jinx::Resource] obj the domain object to lazy-load
      def add_lazy_loader(obj, attributes=nil)
        obj.add_lazy_loader(@lazy_loader, attributes)
      end

      # Loads the content of the given attribute. If the attribute is independent,
      # then the fetched objects are replaced by corresponding cached objects,
      # if cached. The fetched references are persistified with {#persistify}.
      #
      # @param [Jinx::Resource] obj the domain object whose content is to be loaded
      # @param [Symbol] attribute the attribute to load
      # @return [Jinx::Resource, <Jinx::Resource>, nil] the loaded value
      def lazy_load(obj, attribute)
        fetched = fetch_association(obj, attribute) || return
        if obj.class.property(attribute).dependent? then
          persistify(fetched)
        else
          reconcile_fetched(fetched)
        end
      end
      
      # For each fetched domain object, if there is a corresponding cached object,
      # then the reconciled value is that cached object. Otherwise, the reconciled
      # object is the persistified fetched object.
      #
      # @param [Jinx::Resource, <Jinx::Resource>] fetched the fetched domain object(s)
      # @return [Jinx::Resource, <Jinx::Resource>] the reconciled domain object(s)
      def reconcile_fetched(fetched)
        if Enumerable === fetched then
          fetched.map { |ref| reconcile_fetched(ref) }
        else
          reconcile_cached(fetched) or persistify(fetched)
        end
      end
      
      # @param [Jinx::Resource] fetched the fetched domain object
      # @return [Jinx::Resource, nil] the corresponding cached object, if any
      def reconcile_cached(fetched)
        cached = @cache[fetched] if @cache
        if cached then
          logger.debug { "Replaced fetched #{fetched} with cached #{cached}." }
        end
        cached
      end

      # This method clears the given toxic domain objects fetched from the database.
      # The copy nondomain attribute values are set to the fetched object values.
      # The copy fetched reference attribute values are set to a copy of the result references.
      #
      # @quirk caCORE Dereferencing a caCORE search result uncascaded collection attribute
      #   raises a Hibernate missing session error.
      #   This problem is addressed by post-processing the +caCORE+ search result to set the
      #   toxic attributes to an empty value.
      #
      # @quirk caCORE The caCORE search result does not set the obvious inverse attributes,
      #   e.g. children fetched with a parent do not have the children inverse parent attribute
      #   set to the parent. Rather, it is a toxic caCORE reference which must be purged. This
      #   leaves an empty reference which must be lazy-loaded, which is inefficient and inconsistent.
      #   This situation is rectified in this detoxify method by setting the dependent owner
      #   attribute to the fetched owner in the detoxification {Jinx::ReferenceVisitor} copy-match-merge.
      #
      # @return [Jinx::Resource, <Jinx::Resource>] the detoxified object(s)
      def detoxify(toxic)
        return if toxic.nil?
        if toxic.collection? then
          toxic.each { |obj| detoxify(obj) }
        else
          logger.debug { "Detoxifying the toxic caCORE result #{toxic.qp}..." }
          @ftchd_vstr.visit(toxic) { |ref| clear_toxic_attributes(ref) }
          logger.debug { "Detoxified the toxic caCORE result #{toxic.qp}." }
        end
        toxic
      end
      
      # Sets each of the toxic attributes in the given domain object to the corresponding
      # {Metadata#empty_value}.
      #
      # @param [Jinx::Resource] toxic the toxic domain object
      def clear_toxic_attributes(toxic)
        # The result class might not have been previously referenced. In that case,
        # introspect the class.
        ensure_introspected(toxic.class)
        pas = toxic.class.toxic_attributes
        return if pas.empty?
        logger.debug { "Clearing toxic #{toxic.qp} attributes #{pas.to_series}..." }
        pas.each_pair do |pa, prop|
          # skip non-Java attributes
          next unless prop.java_property?
          # the empty or nil value to set
          value = toxic.class.empty_value(pa)
          # Use the Java writer method rather than the standard attribute writer method.
          # The standard attribute writer enforces inverse integrity, which potential requires
          # accessing the current toxic value. The Java writer bypasses inverse integrity.
          reader, writer = prop.property_accessors
          # clear the attribute
          toxic.send(writer, value)
        end
      end
      
      # Persistifies the given domain object and all of its dependents as follows:
      # * Ensure that the object class is introspected.
      # * Set the inverses to enforce inverse integrity.
      #
      # @param (see #persistify_object)
      # @raise [ArgumentError] if obj is a collection and other is not nil
      def persistify(obj, other=nil)
        if obj.collection? then
          if other then Jinx.fail(ArgumentError, "Database reader persistify other argument not supported") end
          obj.each { |ref| persistify(ref) }
          return obj
        end
        # The attribute type is introspected, but the object might be an unintrospected
        # subtype. Introspect the object class if necessary.
        ensure_introspected(obj.class)
        # set the inverses before recursing to dependents
        set_inverses(obj)
        # recurse to dependents before adding a lazy loader to the owner
        obj.dependents.each { |dep| persistify(dep) if dep.identifier }
        persistify_object(obj, other)
      end
      
      # Introspects the given class, if necessary. The class must be either introspected
      # or a subclass of an introspected class.
      #
      # @param [Class] klass the class to introspect if necessary 
      def ensure_introspected(klass)
        unless klass.introspected? then
          sc = klass.superclass
          ensure_introspected(sc)
          logger.debug { "Introspecting the fetched object class #{klass}..." }
          # Resolving the class name in the context of the domain module
          # introspects the class. 
          sc.domain_module.const_get(klass.name.demodulize)
        end
      end
      
      # Takes a {Persistable#snapshot} of obj to track changes, adds a lazy loader and
      # adds the object to the cache.
      #
      # If the other fetched source object is given, then the obj snapshot is updated
      # with the non-nil values from other.
      #
      # @param [Jinx::Resource] obj the domain object to make persistable
      # @param [Jinx::Resource] other the source domain object
      # @return [Jinx::Resource] obj
      def persistify_object(obj, other=nil)
        # take a snapshot of the database content
        snapshot(obj, other)
        # add lazy loader to the unfetched attributes
        add_lazy_loader(obj)
        # add to the cache
        encache(obj)
        obj
      end
      
      # Sets each inversible domain attribute reference inverse to the given domain object.
      # For each inversible domain attribute, if the attribute inverse is a collection,
      # then obj is added to the inverse collection. Otherwise, the inverse attribute
      # is set to obj.
      #
      # @param obj (see #persistify_object)
      def set_inverses(obj)
        obj.class.domain_attributes.each_pair do |pa, prop|
          inv_prop = prop.inverse_property || next
          if inv_prop.collection? then
            obj.send(pa).enumerate { |ref| ref.send(inv_prop.attribute) << obj }
          else
            obj.send(pa).enumerate { |ref| ref.set_property_value(inv_prop.attribute, obj) }
          end
        end
      end
      
      # Take a snapshot of the current object state.
      # If the other fetched object is given, then merge the fetched non-domain attribute
      # values into the obj snapshot, replacing an existing obj non-domain value with the
      # corresponding other attribute value if and only if the other attribute value is non-nil.
      #
      # @param [Jinx::Resource] obj the domain object to snapshot
      # @param [Jinx::Resource] the source domain object
      # @return [Jinx::Resource] the obj snapshot, updated with source content if necessary
      def snapshot(obj, other=nil)
        # take a fresh snapshot
        obj.take_snapshot
        logger.debug { "Snapshot taken of #{obj.qp}." }
        # merge the other object content if available
        obj.merge_into_snapshot(other) if other
      end

      # @param [Jinx::Resource] obj the object to cache
      # @raise [ArgumentError] if the given item does not have an identifier
      def encache(obj)
        @cache ||= create_cache
        @cache.add(obj)
      end    
    
      # @quirk JRuby identifier is not a stable object when fetched from the database, i.e.:
      #     obj.identifier.equal?(obj.identifier) #=> false
      #   This is probably an artifact of jRuby Numeric -> Java Long conversion interaction
      #   combined with hash access use of the eql? method. Work-around is to convert the
      #   identifier to a Ruby Integer.
      #
      # @return [Cache] a new object cache
      def create_cache
        Cache.new do |obj|
          if obj.identifier.nil? then
            Jinx.fail(ArgumentError, "Can't cache object without identifier: #{obj}")
          end
          obj.identifier.to_s.to_i
        end
      end
    end
  end
end