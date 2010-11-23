require 'caruby/util/log'
require 'caruby/util/pretty_print'
require 'caruby/util/inflector'
require 'caruby/util/collection'
require 'caruby/util/validation'

module CaRuby
  # The Persistable mixin adds persistance capability.
  module Persistable
    include Validation

    # @return [LazyLoader] the loader which fetches references on demand
    attr_reader :lazy_loader

    # @return [{Symbol => Object}] the content value hash at the point of the last
    #  take_snapshot call
    attr_reader :snapshot

    # @return [#query, #find, #store, #create, #update, #delete] the data access mediator
    #   for this Persistable
    # @raise [NotImplementedError] if the subclass does not define this method
    def database
      raise NotImplementedError.new("Database operations are not available for #{self}")
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
    def snapshot_taken?
      not @snapshot.nil?
    end

    # Returns whether this Persistable either doesn't have a snapshot or has changed since the last snapshot.
    # This is a conservative condition test that returns false if there is no snaphsot for this Persistable
    # and therefore no basis to determine whether the content changed.
    #
    # @return [Boolean] whether this Persistable's content differs from its snapshot
    def changed?
      @snapshot.nil? or not snapshot_equal_content?
    end

    # @return [<Symbol>] the attributes which differ between the {#snapshot} and current content
    def changed_attributes
      if @snapshot then
        ovh = value_hash(self.class.updatable_attributes)
        @snapshot.diff(ovh).keys
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
    # The initializer is given by either the loader Proc argument or the block provided
    # to this method. The loader takes two arguments, the target object and the attribute to load.
    # If this Persistable already has a lazy loader, then this method is a no-op.
    #
    # Lazy loading is disabled on an attribute after it is invoked on that attribute or when the
    # attribute setter method is called.
    #
    # @param loader [LazyLoader] the lazy loader to add
    # @yield [sources, targets] source => target matcher
    # @yieldparam [<Resource>] sources the fetched domain object match candidates
    # @yieldparam [<Resource>] targets the search target domain objects to match
    # @raise [ValidationError] if this domain object does not have an identifier
    def add_lazy_loader(loader, &matcher)
      # guard against invalid call
      raise ValidationError.new("Cannot add lazy loader to an unfetched domain object: #{self}") if identifier.nil?
      # no-op if there is already a loader
      return if @lazy_loader

      # the attributes to lazy-load
      attrs = self.class.loadable_attributes
      return if attrs.empty?

      # make the lazy loader
      @lazy_loader = LazyLoader.new(self, loader, &matcher)
      # define the reader and writer method overrides for the missing attributes
      loaded = attrs.select { |attr| persistable__add_loader(attr) }
      logger.debug { "Lazy loader added to #{qp} attributes #{loaded.to_series}." } unless loaded.empty?
    end
    
    # Returns the attributes to load on demand. The base attribute list is given by
    # {ResourceAttributes#loadable_attributes}. In additon, if this Persistable has
    # more than one {ResourceDependency#owner_attributes} and one is non-nil, then
    # none of the owner attributes are loaded on demand, since there can be at most
    # one owner and ownership cannot change.
    #
    # @return [<Symbol>] the attributes to load on demand
    def loadable_attributes
      ownr_attrs = self.class.owner_attributes
      if ownr_attrs.size == 2 and ownr_attrs.detect { |attr| send(ownr_attr) } then
        self.class.loadable_attributes - ownr_attrs
      else
        self.class.loadable_attributes
      end
    end

    # Disables this Persistable's lazy loader, if one exists. If a block is given to this
    # method, then the loader is only disabled while the block is executed.
    #
    # @yield the block to call while the loader is suspended
    # @return the result of calling the block, or self if no block is given
    def suspend_lazy_loader
      unless @lazy_loader and @lazy_loader.enabled? then
        return block_given? ? yield : self
      end
      @lazy_loader.disable
      return self unless block_given?
      begin
        yield
      ensure
        @lazy_loader.enable
      end
    end

    # Enables this Persistable's lazy loader, if one exists. If a block is given to this
    # method, then the loader is only enabled while the block is executed.
    #
    # @yield the block to call while the loader is enabled
    # @return the result of calling the block, or self if no block is given
    def resume_lazy_loader
       unless @lazy_loader and @lazy_loader.disabled? then
        return block_given? ? yield : self
      end
      @lazy_loader.enable
      return self unless block_given?
      begin
        yield
      ensure
        @lazy_loader.disable
      end
    end

    # Disables lazy loading of the specified attribute. Lazy loaded is disabled for all attributes
    # if no attribute is specified. This method is a no-op if this Persistable does not have a lazy
    # loader.
    #
    # @param [Symbol] the attribute to remove from the load list, or nil if to remove all attributes
    def remove_lazy_loader(attribute=nil)
      return if @lazy_loader.nil?
      if attribute.nil? then
        self.class.domain_attributes.each { |attr| remove_lazy_loader(attr) }
        @lazy_loader = nil
        return
      end
      
      # the modified accessor method
      reader, writer = self.class.attribute_metadata(attribute).accessors
      # remove the reader override
      disable_singleton_method(reader)
      # remove the writer override
      disable_singleton_method(writer)
    end
    
    # Returns whether this domain object must be fetched to reflect the database state.
    # This default implementation returns whether there are any autogenerated attributes.
    # Subclasses can override with more restrictive conditions.
    #
    # caBIG alert - the auto-generated criterion is a sufficient but not necessary condition
    # to determine whether a save caCORE result does not necessarily accurately reflect the
    # database state. Examples:
    # * caTissue SCG name is auto-generated on SCG create but not SCG update.
    # * caTissue SCG event parameters are not auto-generated on SCG create if the SCG collection
    #   status is Pending, but are auto-generated on SCG update if the SCG status is changed
    #   to Complete.
    # The caBIG application can override this method in a Database subclass to fine-tune the
    # fetch criteria. Adding a more restrictive {#fetch_saved?} condition will will improve
    # performance but not change functionality. 
    #
    # @return [Boolean] whether this domain object must be fetched to reflect the database state
    def fetch_saved?
      not self.class.autogenerated_attributes.empty?
    end

    # Sets the {ResourceAttributes#volatile_nondomain_attributes} to the other fetched value,
    # if different.
    #
    # @param [Resource] other the fetched domain object reflecting the database state
    def copy_volatile_attributes(other)
      self.class.volatile_nondomain_attributes.each do |attr|
        val = send(attr)
        oval = other.send(attr)
        # set the attribute to the other value if it differs from the current value
        unless oval == val then
          # if this error occurs, then there is a serious match-merge flaw
          if val and attr == :identifier then
            raise DatabaseError.new("Can't copy #{other} to #{self} with different identifier")
          end
          # overwrite the current attribute value
          set_attribute(attr, oval)
          logger.debug { "Set #{qp} volatile #{attr} to the fetched #{other.qp} database value #{oval.qp}." }
        end
      end
    end
    
    private

    # Returns whether the {#snapshot} and current content are equal.
    # The attribute values _v_ and _ov_ of the snapshot and current content, resp., are
    # compared with equality determined by {Resource.value_equal?}.
    #
    # @return [Boolean] whether the {#snapshot} and current content are equal
    def snapshot_equal_content?
      vh = @snapshot
      ovh = value_hash(self.class.updatable_attributes)
      if vh.size < ovh.size then
        attr, oval = ovh.detect { |a, v| not vh.has_key?(a) }
        logger.debug { "#{qp} is missing snapshot #{attr} compared to the current value #{oval.qp}." }
        false
      elsif vh.size > ovh.size then
        attr, value = vh.detect { |a, v| not ovh.has_key?(a) }
        logger.debug { "#{qp} has snapshot #{attr} value #{value.qp} not found in current content." }
        false
      else
        vh.all? do |attr, value|
          oval = ovh[attr]
          eq = Resource.value_equal?(oval, value)
          unless eq then
            logger.debug { "#{qp} #{attr} snapshot value #{value.qp} differs from the current value #{oval.qp}." }
          end
          eq
        end
      end
    end
    
    # Adds this Persistable lazy loader to the given attribute unless the attribute already holds a fetched reference.
    # Returns the loader if the loader was added to attribute.
    def persistable__add_loader(attribute)
      # bail if there is already a fetched reference
      return if send(attribute).to_enum.any? { |ref| ref.identifier }
      
      # the accessor methods to modify
      attr_md = self.class.attribute_metadata(attribute)
      reader, writer = attr_md.accessors
      raise NotImplementedError.new("Missing writer method for #{self.class.qp} attribute #{attribute}") if writer.nil?
      
      # define the singleton attribute reader method
      instance_eval "def #{reader}; @lazy_loader ? persistable__load_reference(:#{attribute}) : super; end"
      # define the singleton attribute writer method
      instance_eval "def #{writer}(value); remove_lazy_loader(:#{attribute}); super; end"
      
      @lazy_loader
    end

    # Loads the reference attribute database value into this Persistable.
    #
    # @param [Symbol] attribute the attribute to load
    # @return the attribute value merged from the database value
    def persistable__load_reference(attribute)
      attr_md = self.class.attribute_metadata(attribute)
      # bypass the singleton method and call the class instance method if the lazy loader is disabled
      unless @lazy_loader.enabled? then
        # the modified accessor method
        reader, writer = attr_md.accessors
        return self.class.instance_method(reader).bind(self).call
      end

      # Disable lazy loading first for the attribute, since the reader method might be called in
      # the sequel, resulting in an infinite loop when the lazy loader is retriggered.
      remove_lazy_loader(attribute)
      logger.debug { "Lazy-loading #{qp} #{attribute}..." }
      # the current value
      oldval = send(attribute)
      # load the fetched value
      fetched = @lazy_loader.load(attribute)
      # nothing to do if nothing fetched
      return oldval if fetched.nil_or_empty?
      
      # merge the fetched into the attribute
      logger.debug { "Merging #{qp} fetched #{attribute} value #{fetched.qp}#{' into ' + oldval.qp if oldval}..." }
      matcher = @lazy_loader.matcher
      merged = merge_attribute_value(attribute, oldval, fetched, &matcher)
      # update the snapshot of dependents
      if attr_md.dependent? then
        # the owner attribute
        oattr = attr_md.inverse
        if oattr then
          # update dependent snapshot with the owner, since the owner snapshot is taken when fetched but the
          # owner might be set when the fetched dependent is merged into the owner dependent attribute. 
          merged.enumerate do |dep|
            if dep.snapshot_taken? then
              dep.snapshot[oattr] = self
              logger.debug { "Updated #{qp} #{attribute} fetched dependent #{dep.qp} snapshot with #{oattr} value #{qp}." }
            end
          end
        end
      end
      merged
    end

    # Disables the given singleton attribute accessor method.
    #
    # @param [String, Symbol] name_or_sym the accessor method to disable
    def disable_singleton_method(name_or_sym)
      return unless singleton_methods.include?(name_or_sym.to_s)
      # dissociate the method from this instance
      method = self.method(name_or_sym.to_sym)
      method.unbind
      # JRuby alert - Unbind doesn't work in JRuby 1.1.6. In that case, redefine the singleton method to delegate
      # to the class instance method.
      if singleton_methods.include?(name_or_sym.to_s) then
        args = (1..method.arity).map { |argnum| "arg#{argnum}" }.join(', ')
        instance_eval "def #{name_or_sym}(#{args}); super; end"
      end
    end

    class LazyLoader
      # @return [Proc] the source => target matcher
      attr_reader :matcher
      
      # Creates a new LazyLoader which calls the loader Proc on the subject.
      #
      # @raise [ArgumentError] if the loader is not given to this initializer
      def initialize(subject, loader=nil, &matcher)
        @subject = subject
        # the loader proc from either the argument or the block
        @loader = loader
        @matcher = matcher
        raise ArgumentError.new("Neither a loader nor a block is given to the LazyLoader initializer") if @loader.nil?
        @enabled = true
      end

      # Returns whether this loader is enabled.
      def enabled?
        @enabled
      end

      # Returns whether this loader is disabled.
      def disabled?
        not @enabled
      end

      # Disable this loader.
      def disable
        @enabled = false
      end

      # Enables this loader.
      def enable
        @enabled = true
      end

      # Returns the attribute value loaded from the database.
      # Raises DatabaseError if this loader is disabled.
      def load(attribute)
        raise DatabaseError.new("#{qp} lazy load called on disabled loader") unless enabled?
        @loader.call(@subject, attribute)
      end
    end
  end
end