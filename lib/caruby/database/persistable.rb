require 'jinx/helpers/pretty_print'
require 'jinx/helpers/inflector'
require 'jinx/helpers/collection'
require 'jinx/helpers/validation'

module CaRuby
  # The Persistable mixin adds persistance capability. Every instance which includes Persistable
  # must respond to an overrided {#database} method.
  module Persistable
    # @return [{Symbol => Object}] the content value hash at the point of the last snapshot
    attr_reader :snapshot
      
    # @param [Jinx::Resource, <Jinx::Resource>, nil] obj the object(s) to check
    # @return [Boolean] whether the given object(s) have an identifier
    def self.saved?(obj)
      if obj.nil_or_empty? then
        false
      elsif obj.collection? then
        obj.all? { |ref| saved?(ref) }
      else
        !!obj.identifier
      end
    end
    
    # @param [Jinx::Resource, <Jinx::Resource>, nil] obj the object(s) to check
    # @return [Boolean] whether at least one of the given object(s) does not have an identifier
    def self.unsaved?(obj)
      not (obj.nil_or_empty? or saved?(obj))
    end
    
    # Returns the data access mediator for this domain object.
    # Application #{Jinx::Resource} modules are required to override this method.
    #
    # @return [Database] the data access mediator for this Persistable, if any
    # @raise [DatabaseError] if the subclass does not override this method
    def database
      raise ValidationError.new("#{self} database is missing")
    end
    
    # @return [PersistenceService] the database application service for this Persistable
    def persistence_service
      database.persistence_service(self.class)
    end

    # Fetches the domain objects which match this template from the {#database}.
    #
    # @param path (see Reader#query)
    # @return (see Reader#query)
    # @raise (see #database)
    # @raise (see Reader#query)
    # @see Reader#query
    def query(*path)
      path.empty? ? database.query(self) : database.query(self, *path)
    end

    # Fetches this domain object from the {#database}.
    #
    # @param opts (see Reader#find)
    # @option (see Reader#find)
    # @return (see Reader#find)
    # @raise (see #database)
    # @raise (see Reader#find)
    # @see Reader#find
    def find(opts=nil)
      database.find(self, opts)
    end

    # Creates this domain object in the {#database}.
    #
    # @return (see Writer#create)
    # @raise (see #database)
    # @raise (see Writer#create)
    # @see Writer#create
    def create
      database.create(self)
    end

    # Creates this domain object, if necessary.
    #
    # @raise (see Database#ensure_exists)
    def ensure_exists
      database.ensure_exists(self)
    end
    
    # Saves this domain object in the {#database}.
    #
    # @return (see Writer#save)
    # @raise (see #database)
    # @raise (see Writer#save)
    # @see Writer#save
    def save
      database.save(self)
    end

    alias :store :save

    # Updates this domain object in the {#database}.
    #
    # @return (see Writer#update)
    # @raise (see #database)
    # @raise (see Writer#update)
    # @see Writer#update
    def update
      database.update(self)
    end

    # Deletes this domain object from the {#database}.
    #
    # @return (see Writer#delete)
    # @raise (see #database)
    # @raise (see Writer#delete)
    # @see Writer#delete
    def delete
      database.delete(self)
    end

    alias :== :equal?

    alias :eql? :==

    # Captures the Persistable's updatable attribute base values.
    # The snapshot is subsequently accessible using the {#snapshot} method.
    #
    # @return [{Symbol => Object}] the snapshot value hash
    def take_snapshot
      @snapshot = value_hash(self.class.updatable_attributes)
    end

    # @return [Boolean] whether this Persistable has a {#snapshot}
    def fetched?
      !!@snapshot
    end
    
    # Merges the other domain object non-domain attribute values into this domain object's snapshot,
    # An existing snapshot value is replaced by the corresponding other attribute value.
    #
    # @param [Jinx::Resource] other the source domain object
    # @raise [ValidationError] if this domain object does not have a snapshot
    def merge_into_snapshot(other)
      if @snapshot.nil? then
        raise ValidationError.new("Cannot merge #{other.qp} content into #{qp} snapshot, since #{qp} does not have a snapshot.")
      end
      # the non-domain attribute => [target value, other value] difference hash
      delta = diff(other)
      # the difference attribute => other value hash, excluding nil other values
      dvh = delta.transform_value { |d| d.last }
      return if dvh.empty?
      logger.debug { "#{qp} differs from database content #{other.qp} as follows: #{delta.filter_on_key { |pa| dvh.has_key?(pa) }.qp}" }
      logger.debug { "Setting #{qp} snapshot values from other #{other.qp} values to reflect the database state: #{dvh.qp}..." }
      # update the snapshot from the other value to reflect the database state
      @snapshot.merge!(dvh)
    end
    
    # Returns whether this Persistable either doesn't have a snapshot or has changed since the last snapshot.
    # This is a conservative condition test that returns false if there is no snaphsot for this Persistable
    # and therefore no basis to determine whether the content changed. If the attribute parameter is given,
    # then only that attribute is checked for a change. Otherwise, all attributes are checked.
    #
    # @param [Symbol, nil] attribute the optional attribute to check.
    # @return [Boolean] whether this Persistable's content differs from its snapshot
    def changed?(attribute=nil)
      @snapshot.nil? or not snapshot_equal_content?(attribute)
    end

    # @return [<Symbol>] the attributes which differ between the {#snapshot} and current content
    def changed_attributes
     if @snapshot then
        ovh = value_hash(self.class.updatable_attributes)
        diff = @snapshot.diff(ovh) { |pa, v, ov| Jinx::Resource.value_equal?(v, ov) }
        diff.keys
      else
        self.class.updatable_attributes
      end
    end

    # Lazy loads the attributes. If a block is given to this method, then the attributes are determined
    # by calling the block with this Persistable as a parameter. Otherwise, the default attributes
    # are the unfetched domain attributes.
    #
    # Each of the attributes which does not already hold a non-nil or non-empty value
    # will be loaded from the database on demand.
    # This method injects attribute value initialization into each loadable attribute reader.
    # The initializer is given by either the loader Proc argument.
    # The loader takes two arguments, the target object and the attribute to load.
    # If this Persistable already has a lazy loader, then this method is a no-op.
    #
    # Lazy loading is disabled on an attribute after it is invoked on that attribute or when the
    # attribute setter method is called.
    #
    # @param loader [LazyLoader] the lazy loader to add
    def add_lazy_loader(loader, attributes=nil)
      # guard against invalid call
      if identifier.nil? then raise ValidationError.new("Cannot add lazy loader to an unfetched domain object: #{self}") end
      # the attributes to lazy-load
      attributes ||= loadable_attributes
      return if attributes.empty?
      # define the reader and writer method overrides for the missing attributes
      pas = attributes.select { |pa| inject_lazy_loader(pa) }
      logger.debug { "Lazy loader added to #{qp} attributes #{pas.to_series}." } unless pas.empty?
    end
    
    # Returns the attributes to load on demand. The base attribute list is given by the
    # {Propertied#loadable_attributes} whose value is nil or empty.
    # In addition, if this Persistable has more than one {Domain::Dependency#owner_attributes}
    # and one is non-nil, then none of the owner attributes are loaded on demand,
    # since there can be at most one owner and ownership cannot change.
    #
    # @return [<Symbol>] the attributes to load on demand
    def loadable_attributes
      pas = self.class.loadable_attributes.select { |pa| send(pa).nil_or_empty? }
      ownr_attrs = self.class.owner_attributes
      # If there is an owner, then variant owners are not loaded.
      if ownr_attrs.size > 1 and ownr_attrs.any? { |pa| not send(pa).nil_or_empty? } then
        pas - ownr_attrs
      else
        pas
      end
    end

    # Disables lazy loading of the specified attribute. Lazy loaded is disabled for all attributes
    # if no attribute is specified. This method is a no-op if this Persistable does not have a lazy
    # loader.
    #
    # @param [Symbol] the attribute to remove from the load list, or nil if to remove all attributes
    def remove_lazy_loader(attribute=nil)
      if attribute.nil? then
        return self.class.domain_attributes.each { |pa| remove_lazy_loader(pa) }
      end
      # the modified accessor method
      reader, writer = self.class.property(attribute).accessors
      # remove the reader override
      disable_singleton_method(reader)
      # remove the writer override
      disable_singleton_method(writer)
    end
    
    # Wrap +Resource.dump+ to disable the lazy-loader while printing.
    def dump
      do_without_lazy_loader { super }
    end
    
    # Executes the given block with the database lazy loader disabled, if any.
    #
    # @yield the block to execute
    def do_without_lazy_loader(&block)
      if database then
        database.lazy_loader.disable(&block)
      else
        yield
      end
    end

    # Validates this domain object and its #{Propertied#unproxied_savable_template_attributes}
    # for consistency and completeness prior to a database create operation.
    # An object is valid if it contains a non-nil value for each mandatory attribute.
    # Objects which have already been validated are skipped.
    #
    # A Persistable class should not override this method, but override the
    # private {#validate_local} method instead.
    #
    # @return [Persistable] this domain object
    # @raise [Jinx::ValidationError] if the object state is invalid
    def validate(autogenerated=false)
      if (identifier.nil? or autogenerated) and not @validated then
        validate_local
        @validated = true
      end
      self.class.unproxied_savable_template_attributes.each do |pa|
        send(pa).enumerate { |dep| dep.validate }
      end
      self
    end
        
    # Sets the default attribute values for this auto-generated domain object.
    def add_defaults_autogenerated
      add_defaults_recursive
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
      key_props = self.class.primary_key_attributes
      return key_props if key_searchable?(key_props)
      key_props = self.class.secondary_key_attributes
      return key_props if key_searchable?(key_props)
      key_props = self.class.alternate_key_attributes
      return key_props if key_searchable?(key_props)
    end
    
    # Returns this domain object's attributes which must be fetched to reflect the database state.
    # This default implementation returns the {Propertied#autogenerated_logical_dependent_attributes}
    # if this domain object does not have an identifier, or an empty array otherwise.
    # Subclasses can override to relax or restrict the condition.
    #
    # @quirk caCORE the auto-generated criterion is a necessary but not sufficient condition
    #   to determine whether a save caCORE result reflects the database state. Example:
    #   * caTissue SCG event parameters are not auto-generated on SCG create if the SCG collection
    #     status is Pending, but are auto-generated on SCG update if the SCG status is changed
    #     to Complete. By contrast, the SCG specimens are auto-generated on SCG create, even if
    #     the status is +Pending+.
    #   The caBIG application can override this method in a Database subclass to fine-tune the
    #   fetch criteria. Adding a more restrictive {#fetch_saved?} condition will will improve
    #   performance but not change functionality.
    #
    # @quirk caCORE a saved attribute which is cascaded but not fetched must be fetched in
    #   order to reflect the database identifier in the saved object.
    #
    # @param [Database::Operation] the save operation
    # @return [<Symbol>] whether this domain object must be fetched to reflect the database state
    def saved_attributes_to_fetch(operation)
      # only fetch a create, not an update (note that subclasses can override this condition)
      if operation.type == :create or operation.autogenerated? then
        # Filter the class saved fetch attributes for content.
        self.class.saved_attributes_to_fetch.select { |pa| not send(pa).nil_or_empty? }
      else
        Array::EMPTY_ARRAY
      end
    end
    
    # Relaxes the {#saved_attributes_to_fetch} condition for a SCG as follows:
    # * If the SCG status was updated from +Pending+ to +Collected+, then fetch the saved SCG event parameters.
    # 
    # @param (see #saved_attributes_to_fetch)
    # @return (see #saved_attributes_to_fetch)
    def autogenerated?(operation)
      operation == :update && status_changed_to_complete? ? EVENT_PARAM_ATTRS : super
    end
    
    def fetch_autogenerated?(operation)
      # only fetch a create, not an update (note that subclasses can override this condition)
      operation == :update
      # Check for an attribute with a value that might need to be changed in order to
      # reflect the auto-generated database content.
      self.class.autogenerated_logical_dependent_attributes.select { |pa| not send(pa).nil_or_empty? }
    end
    
    # Returns whether this domain object must be fetched to reflect the database state.
    # This default implementation returns whether this domain object was created and
    # there are any autogenerated attributes. Subclasses can override to relax or restrict
    # the condition.
    #
    # @quirk caCORE The auto-generated criterion is a necessary but not sufficient condition
    #   to determine whether a save caCORE result reflects the database state. Example:
    #   * caTissue SCG event parameters are not auto-generated on SCG create if the SCG collection
    #     status is Pending, but are auto-generated on SCG update if the SCG status is changed
    #     to Complete. By contrast, the SCG specimens are auto-generated on SCG create, even if
    #     the status is +Pending+.
    #
    #   The caBIG application can override this method in a Database subclass to fine-tune the
    #   fetch criteria. Adding a more restrictive {#fetch_saved?} condition will will improve
    #   performance but not change functionality.
    #
    # @quirk caCORE A saved attribute which is cascaded but not fetched must be fetched in
    #   order to reflect the database identifier in the saved object.
    #
    # TODO - this method is no longeer used. Should it be? If not, remove here and in catissue
    # subclasses.
    #
    # @return [Boolean] whether this domain object must be fetched to reflect the database state
    def fetch_saved?
      # only fetch a create, not an update (note that subclasses can override this condition)
      return false if identifier
      # Check for an attribute with a value that might need to be changed in order to
      # reflect the auto-generated database content.
      ag_attrs = self.class.autogenerated_attributes
      return false if ag_attrs.empty?
      ag_attrs.any? { |pa| not send(pa).nil_or_empty? }
    end

    # Sets the {Propertied#volatile_nondomain_attributes} to the other fetched value,
    # if different.
    #
    # @param [Jinx::Resource] other the fetched domain object reflecting the database state
    def copy_volatile_attributes(other)
      pas = self.class.volatile_nondomain_attributes
      return if pas.empty?
      logger.debug { "Merging volatile attributes #{pas.to_series} from #{other.qp} into #{qp}..." }
      pas.each do |pa|
        val = send(pa)
        oval = other.send(pa)
        if val.nil? then
          # Overwrite the current attribute value.
          set_property_value(pa, oval)
          logger.debug { "Set #{qp} volatile #{pa} to the fetched #{other.qp} database value #{oval.qp}." }
        elsif oval != val and pa == :identifier then
          # If this error occurs, then there is a serious match-merge flaw. 
          raise DatabaseError.new("Can't copy #{other} to #{self} with different identifier")
        end
      end
    end
    
    private

    # @return [Boolean] whether the given key attributes is non-empty and each attribute in the key has a non-nil value
    def key_searchable?(attributes)
      not (attributes.empty? or attributes.any? { |pa| send(pa).nil? })
    end

    # Returns whether the {#snapshot} and current content are equal.
    # The attribute values _v_ and _ov_ of the snapshot and current content, resp., are
    # compared with equality determined by {Jinx::Resource.value_equal?}.
    #
    # @param (see #changed?)
    # @return [Boolean] whether the {#snapshot} and current content are equal
    def snapshot_equal_content?(attribute=nil)
      if attribute then
        value = send(attribute)
        ssval = @snapshot[attribute]
        eq = Jinx::Resource.value_equal?(value, ssval)
        unless eq then
          logger.debug { "#{qp} #{attribute} snapshot value #{ssval.qp} differs from the current value #{value.qp}." }
        end
        return eq
      end
      
      vh = value_hash(self.class.updatable_attributes)
      
      # KLUDGE TODO - confirm this is still a problem and fix.
      # In the Galena frozen migration example, the SpecimenPosition snapshot doesn't include the identifier.
      # This bug could be related to the problem of an abstract DomainObject not being added as a domain module class.
      # Work around this here by setting the snapshot identifier.
      # See the ClinicalTrials::Jinx::Resource rubydoc for more info.
      if vh[:identifier] and not @snapshot[:identifier] then
        @snapshot[:identifier] = vh[:identifier]
      end
      # END OF KLUDGE
      
      if @snapshot.size < vh.size then
        pa, pv = vh.detect { |a, v| not @snapshot.has_key?(a) }
        logger.debug { "#{qp} is missing snapshot #{pa} compared to the current value #{pv.qp}." }
        false
      elsif @snapshot.size > vh.size then
        pa, value = @snapshot.detect { |a, v| not vh.has_key?(a) }
        logger.debug { "#{qp} has snapshot #{pa} value #{value.qp} not found in current content." }
        false
      else
        @snapshot.all? do |pa, ssval|
          pv = vh[pa]
          eq = Jinx::Resource.value_equal?(pv, ssval)
          unless eq then
            logger.debug { "#{qp} #{pa} snapshot value #{ssval.qp} differs from the current value #{pv.qp}." }
          end
          eq
        end
      end
    end
    
    # Adds this Persistable lazy loader to the given attribute unless the attribute already holds a
    # fetched reference.
    #
    # @param [Symbol] attribute the attribute to mod
    # @return [Boolean] whether a loader was added to the attribute
    def inject_lazy_loader(attribute)
      # bail if there is already a value
      return false if attribute_loaded?(attribute)
      # the accessor methods to modify
      reader, writer = self.class.property(attribute).accessors
      # The singleton attribute reader method loads the reference once and thenceforth calls the
      # standard reader.
      instance_eval "def #{reader}; load_reference(:#{attribute}); end"
      # The singleton attribute writer method removes the lazy loader once and thenceforth calls
      # the standard writer.
      instance_eval "def #{writer}(value); remove_lazy_loader(:#{attribute}); super; end"
      true
    end
    
    # @param (see #inject_lazy_loader)
    # @return [Boolean] whether the attribute references one or more domain objects, and each
    #   referenced object has an identifier
    def attribute_loaded?(attribute)
      value = transient_value(attribute)
      return false if value.nil_or_empty?
      Enumerable === value ? value.all? { |ref| ref.identifier } : value.identifier
    end

    # Loads the reference attribute database value into this Persistable.
    #
    # @param [Symbol] attribute the attribute to load
    # @return the attribute value merged from the database value
    def load_reference(attribute)
      ldr = database.lazy_loader
      # bypass the singleton method and call the class instance method if the lazy loader is disabled
      return transient_value(attribute) unless ldr.enabled?
      
      # First disable lazy loading for the attribute, since the reader method is called by the loader.
      remove_lazy_loader(attribute)
      # load the fetched value
      merged = ldr.load(self, attribute)
      
      # update dependent snapshots if necessary
      pa = self.class.property(attribute)
      if pa.dependent? then
        # the owner attribute
        oattr = pa.inverse
        if oattr then
          # update dependent snapshot with the owner, since the owner snapshot is taken when fetched but the
          # owner might be set when the fetched dependent is merged into the owner dependent attribute. 
          merged.enumerate do |dep|
            if dep.fetched? then
              dep.snapshot[oattr] = self
              logger.debug { "Updated the #{qp} fetched #{attribute} dependent #{dep.qp} snapshot with #{oattr} value #{qp}." }
            end
          end
        end
      end

      merged
    end
    
    # @param (see #load_reference)
    # @return the in-memory attribute value, without invoking the lazy loader
    def transient_value(attribute)
      self.class.instance_method(attribute).bind(self).call
    end

    # Disables the given singleton attribute accessor method.
    #
    # @param [String, Symbol] name_or_sym the accessor method to disable
    def disable_singleton_method(name_or_sym)
      return unless singleton_methods.include?(name_or_sym.to_s)
      # dissociate the method from this instance
      method = self.method(name_or_sym.to_sym)
      method.unbind
      # JRuby unbind doesn't work in JRuby 1.1.6. In that case, redefine the singleton method to delegate
      # to the class instance method.
      if singleton_methods.include?(name_or_sym.to_s) then
        args = (1..method.arity).map { |argnum| "arg#{argnum}" }.join(', ')
        instance_eval "def #{name_or_sym}(#{args}); super; end"
      end
    end
  end
end