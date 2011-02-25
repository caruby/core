require 'caruby/migration/resource_module'

module CaRuby
  # A Migratable mix-in adds migration support for Resource domain objects.
  # For each migration Resource created by a CaRuby::Migrator, the migration process
  # is as follows:
  #
  # 1. The migrator creates the Resource using the empty constructor.
  #
  # 2. Each input field value which maps to a Resource attribute is obtained from the
  #    migration source.
  #
  # 3. If the Resource class implements a method +migrate_+_attribute_ for the
  #    migration _attribute_, then that migrate method is called with the input value
  #    argument. If there is a migrate method, then the attribute is set to the
  #    result of calling that method, otherwise the attribute is set to the original
  #    input value.
  #
  #    For example, if the +Name+ input field maps to +Participant.name+, then a
  #    custom +Participant+ +migrate_name+ shim method can be defined to reformat
  #    the input name.
  #
  # 4. The Resource attribute is set to the (possibly modified) value.
  #
  # 5. After all input fields are processed, then {#migration_valid?} is called to
  #    determine whether the migrated object can be used. {#migration_valid?} is true
  #    by default, but a migration shim can add a validation check,
  #    migrated Resource class to return false for special cases.
  #
  #    For example, a custom +Participant+ +migration_valid?+ shim method can be
  #    defined to return whether there is a non-empty input field value.
  #
  # 6. After the migrated objects are validated, then the Migrator fills in
  #    dependency hierarchy gaps. For example, if the Resource class +Participant+
  #    owns the +enrollments+ dependent which in turn owns the +encounters+ dependent
  #    and the migration has created a +Participant+ and an +Encounter+ but no +Enrollment+,
  #    then an empty +Enrollment+ is created which is owned by the migrated +Participant+
  #    and owns the migrated +Encounter+.
  #
  # 7. After all dependencies are filled in, then the independent references are set
  #    for each created Resource (including the new dependents). If a created
  #    Resource has an independent non-collection Resource reference attribute
  #    and there is a migrated instance of that attribute type, then the attribute
  #    is set to that migrated instance.
  #
  #    For example, if +Enrollment+ has a +study+ attribute and there is a
  #    single migrated +Study+ instance, then the +study+ attribute is set
  #    to that migrated +Study+ instance.
  #
  #    If the referencing class implements a method +migrate_+_attribute_ for the
  #    migration _attribute_, then that migrate method is called with the referenced
  #    instance argument. The result is used to set the attribute. Otherwise, the
  #    attribute is set to the original referenced instance.
  #
  #    There must be a single unambiguous candidate independent instance, e.g. in the
  #    unlikely but conceivable case that two +Study+ instances are migrated, then the
  #    +study+ attribute is not set. Similarly, collection attributes are not set,
  #    e.g. a +Study+ +protocols+ attribute is not set to a migrated +Protocol+
  #    instance.
  #
  # 8. The {#migrate} method is called to complete the migration. As described in the
  #    method documentation, a migration shim Resource subclass can override the
  #    method for custom migration processing, e.g. to migrate the ambiguous or
  #    collection attributes mentioned above, or to fill in missing values.
  #
  #    Note that there is an extensive set of attribute defaults defined in
  #    the CaRuby::ResourceMetadata application domain classes. These defaults
  #    are applied in a migration database save action and need not be set in
  #    a migration shim. For example, if an acceptable default for a +Study+
  #    +active?+ flag is defined in the +Study+ meta-data, then the flag does not
  #    need to be set in a migration shim.
  module Migratable
    # Completes setting this Migratable domain object's attributes from the given input row.
    # This method is responsible for migrating attributes which are not mapped
    # in the configuration. It is called after the configuration attributes for
    # the given row are migrated and before {#migrate_references}.
    #
    # This base implementation is a no-op.
    # Subclasses can modify this method to complete the migration. The overridden
    # methods should call +super+ to pick up the superclass migration.
    #
    # @param [Hash] row the input row
    # @param [Enumerable] migrated the migrated instances, including this Resource
    def migrate(row, migrated)
    end

    # Returns whether this migration target domain object is valid. The default is true
    # if this domain object either has no owner or its owner is valid.
    # A migration shim should override this method on the target if there are conditions
    # which determine whether the migration should be skipped for this target object.
    #
    # @return [Boolean] whether this migration target domain object is valid
    def migration_valid?
      # check that the owner is be valid
      ownr = owner
      ownr.nil? or ownr.migration_valid?
    end

    # Migrates this domain object's migratable references. This method is called by the
    # CaRuby::Migrator and should not be overridden by subclasses. Subclasses tailor
    # individual reference attribute migration by defining a +migrate_+_attribute_ method
    # for the _attribute_ to modify.
    #
    # The migratable reference attributes consist of the non-collection
    # {ResourceAttributes#saved_independent_attributes} and 
    # {ResourceAttributes#unidirectional_dependent_attributes} which don't already have a value.
    # For each such migratable attribute, if there is a single instance of the attribute
    # type in the given migrated domain objects, then the attribute is set to that
    # migrated instance.
    #
    # If the attribute is associated with a method in mth_hash, then that method is called
    # on the migrated instance and input row. The attribute is set to the method return value.
    # mth_hash includes an entry for each +migrate_+_attribute_ method defined by this
    # Resource's class.
    #
    # @param [{Symbol => Object}] row the input row field => value hash
    # @param [<Resource>] migrated the migrated instances, including this Resource
    # @param [{Symbol => String}] mth_hash a hash that associates this domain object's
    #   attributes to migration method names
    def migrate_references(row, migrated, mth_hash=nil)
      self.class.saved_independent_attributes.each do |attr|
        ref = migratable__reference_value(attr, migrated) 
        migratable__set_reference(attr, ref, row, mth_hash) if ref
      end
      self.class.unidirectional_dependent_attributes.each do |attr|
        ref = migratable__reference_value(attr, migrated) 
        migratable__set_reference(attr, ref, row, mth_hash) if ref
      end
    end
    
    private
    
    # @param [Symbol] attribute the reference attribute to get
    # @param migrated (see #migrate_references)
    # @return [Resource, nil] the migrated value to which the attribute will be set
    def migratable__reference_value(attribute, migrated)
      # skip non-nil attributes
      return if send(attribute)
      # the attribute metadata, used for type information
      attr_md = self.class.attribute_metadata(attribute)
      # skip collection attributes
      return if attr_md.collection?
      # the migrated references which are instances of the attribute type
      refs = migrated.select { |other| other != self and attr_md.type === other }
      # skip ambiguous references
      return unless refs.size == 1
      # the single reference
      ref = refs.first
    end
    
    # Sets the given migrated domain object attribute to the given reference.
    #
    # If the attribute is associated to a method in mth_hash, then that method is called on
    # the migrated instance and input row. The attribute is set to the method return value.
    # mth_hash includes an entry for each +migrate_+_attribute_ method defined by this
    # Resource's class.
    #
    # @param [Symbol] (see #migratable__reference_value)
    # @param [Resource] ref the migrated reference
    # @param row (see #migrate_references)
    # @param mth_hash (see #migrate_references)
    def migratable__set_reference(attribute, ref, row, mth_hash=nil)
      # the shim method, if any
      mth = mth_hash[attribute] if mth_hash
      # if there is a shim method, then call it
      ref = send(mth, ref, row) if mth and respond_to?(mth)
      return if ref.nil?
      logger.debug { "Setting #{qp} #{attribute} to migrated #{ref.qp}..." }
      set_attribute(attribute, ref)
    end
  end
end