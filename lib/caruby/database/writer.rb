require 'caruby/util/collection'
require 'caruby/util/pretty_print'
require 'caruby/domain/reference_visitor'
require 'caruby/database/saved_merger'
require 'caruby/database/store_template_builder'

module CaRuby
  class Database
    # Database store operation mixin.
    module Writer
      # Adds store capability to this Database.
      def initialize
        super
        @cr_tmpl_bldr = StoreTemplateBuilder.new(self) { |ref| ref.class.creatable_domain_attributes }
        @upd_tmpl_bldr = StoreTemplateBuilder.new(self) { |ref| updatable_domain_attributes(ref) }
        @svd_mrgr = SavedMerger.new(self)
      end

      # Creates the specified domain object obj and returns obj. The pre-condition for this method is as
      # follows:
      # * obj is a well-formed domain object with the necessary required attributes as determined by the
      #   {Resource#validate} method
      # * obj does not have a database identifier attribute value
      # * obj does not yet exist in the database
      # The post-condition is that obj is created and assigned a database identifier.
      #
      # An object referenced by obj is created or updated if and only if the change operation on the referenced
      # object is necesssary to create obj. This behavior differs from the standard +caCORE+ behavior in that
      # the client does not need to embed implicit prescriptive application rules in the sequence of database
      # operation calls. The goal is to reflect the caRuby client declarative intent:
      # * caRuby will do whatever is necessary to reflect the object state to the database.
      # * No other changes will be made to the database.
      #
      # By definition, a dependent object is not created directly. If obj is dependent and references its owner,
      # then this method delegates to the owner by calling {#store} on the owner. The owner store operation will
      # create or update the owner using {#store} and create the dependent obj in the process.
      #
      # _Note_: the dependent identifier is not set if the owner dependent attribute is a collection and
      # the dependent class does not have secondary key attributes. In that case, there is no reliable +caCORE+
      # query mechanism to match the obj dependent to a created or fetched dependent. The owner dependent
      # collection content is replaced by new dependent objects fetched from the database, e.g. given a
      # +dependent+ in the +owner+ +dependents+ collection, then:
      #   dependents_count = owner.dependents.size
      #   owner.dependents.include?(dependent) #=> true
      #   database.create(dependent).identifier #=> nil
      #   owner.dependents.include?(dependent) #=> false
      #   owner.dependents.size == dependents_count #=> true
      #
      # If obj is not dependent, then the create strategy is as follows:
      # * add default attribute values using {Resource#add_defaults}
      # * validate obj using {Resource#validate}
      # * ensure that all saved independent reference attribute values exist in the database, creating
      #   them if necessary
      # * ensure that all dependent reference attribute values can be created according to this set of rules
      # * make a template for obj and its references that will result in saving obj saved attributes
      #   to the database
      # * submit the template to the application service creation method.
      # * copy the new database identifier to each created object, i.e. the transitive closure of obj and
      #   its dependents
      #
      # @param [Resource] the domain object to create
      # @return [Resource] obj
      # @raise [DatabaseError] if the database operation fails
      def create(obj)
        # guard against recursive call back into the same operation
        # the only allowed recursive call is a dependent create which first creates the owner
        if recursive_save?(obj, :create) then
          raise DatabaseError.new("Create #{obj.qp} recursively called in context #{print_operations}")
        elsif obj.identifier then
          raise DatabaseError.new("Create unsuccessful since #{obj.qp} already has identifier #{obj.identifier}")
        end
        # create the object
        perform(:create, obj) { create_object(obj) }
      end

      # Updates the specified domain object obj. The pre-condition for this method is that obj exists in the
      # database and has a database identifier attribute value. The post-condition is that the database is
      # changed to reflect the obj state. Each dependent object referenced by obj is also created or updated.
      # No other object referenced by obj is changed.
      #
      # The update strategy is the same as the {#create} strategy with the following exceptions:
      # * validate that obj has a database identifier
      # * the template is submitted to the application service update method
      #
      # Raises DatabaseError if the database operation fails.
      def update(obj)
        # guard against a recursive call back into the same operation.
        if recursive_save?(obj, :update) then
          raise DatabaseError.new("Update #{obj.qp} recursively called in context #{print_operations}")
        end
        # update the object
        perform(:update, obj) { update_object(obj) }
      end

      # Updates the specified domain object if it exists, otherwise creates a new domain object.
      #
      # The database is queried based on the object attributes. If a match is found,
      # then the obj database identifier attribute is set and update is called.
      # If no matching database record is found, then the object is persisted using create.
      #
      # @see #create 
      # @see #update
      #
      #@param [Resource] obj the domain object to save
      # @return [Resource] obj
      # @raise [DatabaseError] if the database operation fails
      def save(obj)
        logger.debug { "Storing #{obj}..." }
        # add defaults now, since a default key value could be used in the existence check
        obj.add_defaults
        # if obj exists then update it, otherwise create it
        exists?(obj) ? update(obj) : create(obj)
      end

      alias :store :save

      # Deletes the specified domain object obj.
      #
      # Note that some applications restrict or forbid delete operations. Check the specific application
      # documentation to determine whether deletion is supported.
      #
      #@param [Resource] obj the domain object to delete
      # @raise [DatabaseError] if the database operation fails
      def delete(obj)
        perform(:delete, obj) { delete_object(obj) }
      end

      # Creates the domain object obj, if necessary.
      #
      # Raises ArgumentError if obj is nil or empty.
      # Raises DatabaseError if obj could not be created.
      # The return value is undefined.
      def ensure_exists(obj)
        raise ArgumentError.new("Database ensure_exists is missing a domain object argument") if obj.nil_or_empty?
        obj.enumerate { |ref| find(ref, :create) unless ref.identifier }
      end

      # Returns whether there is already the given obj operation in progress that is not in the scope of
      # an operation performed on a dependent obj owner, i.e. a second obj save operation of the same type
      # is only allowed if the obj operation was delegated to an owner save which in turn saves the dependent
      # obj.
      #
      # @param [Resource] obj the domain object to save
      # @param [Symbol] operation the +:create+ or +:update+ save operation
      # @return [Boolean] whether the save operation is redundant
      def recursive_save?(obj, operation)
        @operations.detect { |op| op.type == operation and op.subject == obj } and
        @operations.last.subject != obj.owner
      end

      private

      # Creates obj as follows:
      # * if obj has an uncreated owner, then store the owner, which in turn will create a physical dependent
      # * otherwise, create a storable template. The template is a copy of obj containing a recursive copy
      #   of each saved obj reference and resolved independent references
      # * submit the template to the create application service
      # * update the obj dependency transitive closure content from the create result
      # * add a lazy-loader to obj for unfetched domain references
      #
      # @param (see #create)
      # @return [Resource] obj
      def create_object(obj)
        # add obj to the transients set
        @transients << obj
        begin
          # A dependent of an uncreated owner can be created by creating the owner.
          # Otherwise, create obj from a template.
          create_as_dependent(obj) or
          create_from_template(obj) or
          raise DatabaseError.new("#{obj.class.qp} is not creatable in context #{print_operations}")
        ensure
          # since obj now has an id, removed from transients set
          @transients.delete(obj)
        end
        # return the created object
        obj
      end

      # Attempts to create the domain object dep as a dependent by storing its owner.
      # Returns dep if dep is dependent and could be created, nil otherwise.
      #
      # A physical dependent is created by its parent.
      # A logical dependent is created by its parent unless the parent already exists.
      # If the logical parent exists, then dep must be created.
      #
      #@param [Resource] dep the dependent domain object to create
      # @return [Resource] dep
      def create_as_dependent(dep)
        # bail if not dependent or owner is not set
        owner = dep.owner || return
        unless owner.identifier then
          logger.debug { "Adding #{owner.qp} dependent #{dep.qp} defaults..." }
          dep.add_defaults
          logger.debug { "Ensuring that dependent #{dep.qp} owner #{owner.qp} exists..." }
          ensure_exists(owner)
        end

        # If the dependent was created as a side-effect of creating the owner, then we are done.
        if dep.identifier then
          logger.debug { "Created dependent #{dep.qp} by saving owner #{owner.qp}." }
          return dep
        end

        # If there is a saver proxy, then use the proxy.
        if dep.class.method_defined?(:saver_proxy) then
          save_with_proxy(dep)
          # remove obj from transients to clear previous fetch, if any
          @transients.delete(dep)
          logger.debug { "Fetching #{dep.qp} to reflect the proxy save..." }
          find(dep)
        end
      end
     
      # Saves the given domain object using a proxy.
      #
      # @param [Resource] obj the proxied domain object
      # @return [Resource] obj
      # @raise [DatabaseError] if obj does not have a proxy
      def save_with_proxy(obj)
        proxy = obj.saver_proxy
        if proxy.nil? then raise DatabaseError.new("#{obj.class.qp} does not have a proxy") end
        logger.debug { "Saving #{obj.qp} by creating the proxy #{proxy}..." }
        create(proxy)
        logger.debug { "Created the #{obj.qp} proxy #{proxy}." }
        logger.debug { "Udating the #{obj.qp} snapshot to reflect the proxy save..." }
        obj.take_snapshot
        obj
      end

      # Creates obj by submitting a template to the persistence service. Ensures that the domain
      # objects referenced by the created obj exist and are correctly stored.
      #
      # caCORE alert - submitting the object directly for create runs into various caTissue bizlogic
      # traps, e.g. Participant CPR is not cascaded but Participant bizlogic checks that each CPR
      # referenced by Participant is ready to be created. It is treacherous to make assumptions
      # about what caTissue bizlogic will or will not check. Therefore, the safer strategy is to
      # build a template for submission that includes only the object cascaded and direct
      # non-cascaded independent references. The independent references are created if necessary.
      # The template thus includes only as much content as can safely pass through the caTissue
      # bizlogic minefield.
      #
      # caCORE alert - caCORE create does not update the submitted object to reflect the created
      # content. The create result is a separate object, which in turn does not always reflect
      # the created content, e.g. caTissue ignores auto-generated attributes such as Container
      # name. Work-around is to merge the create result into the object being created, being
      # careful to merge only the fetched content in order to avoid the dreaded out-of-session
      # error message. The post-create cascaded dependent hierarchy is traversed to capture
      # the created state for each created object.
      #
      # The ignored content is handled separately by fetching the ignored content from
      # the database, comparing it to the desired content as reflected in the submitted
      # create argument object, and submitting a post-create caCORE update as necessary to
      # force caCORE to reflect the desired content. This is complicated by the various
      # auto-generation schemes, e.g. in caTissue, that require a careful fetch, match and
      # merge logic to make sense of how what was actually created corresponds to the desired
      # content expressed in the create argument object graph.
      #
      # There are thus several objects involved in the create process:
      # * the object to create
      # * the template for caCORE createObject submission
      # * the caCORE createObject result
      # * the post-create fetched object that reflects the persistent content
      # * the template for post-create caCORE updateObject submission
      #
      # This object menagerie is unfortunate but unavoidable if we are to navigate the treacherous
      # caCORE create process and ensure that:
      # 1. the database reflects the create argument.
      # 2. the created object reflects the database content.
      #
      # @param (see #create)
      # @return obj
      def create_from_template(obj)
        # The create template. Independent saved references are created as necessary.
        tmpl = build_create_template(obj)        
        save_with_template(obj, tmpl) { |svc| svc.create(tmpl) }
        
        # If obj is a top-level create, then ensure that remaining references exist.
        if @operations.first.subject == obj then
          refs = obj.suspend_lazy_loader { obj.references.reject { |ref| ref.identifier } }
          logger.debug { "Ensuring that created #{obj.qp} references exist: #{refs.qp}..." } unless refs.empty?
          refs.each { |ref| ensure_exists(ref) }
        end
        
        obj
      end
      
      def build_create_template(obj)
        @cr_tmpl_bldr.build_template(obj)
      end
#
      # caCORE alert - application create logic might ignore a non-domain attribute value,
      # e.g. the caTissue StorageContainer auto-generated name attribute. In other cases, the application
      # always ignores a non-domain attribute value, so the object should not be saved even if it differs
      # from the stored result, e.g. the caTissue CollectionProtocolRegistration unsaved
      # registration_date. The work-around is to check whether the create result
      # differs from the create argument for the auto-generated updatable attributes, and, if so,
      # to update the saved object.
      #
      # This method returns whether the saved obj differs from the stored source for any
      # {ResourceAttributes#autogenerated_nondomain_attributes}.
      #
      # @param [Resource] the created domain object
      # @param [Resource] the stored database content source domain object
      # @return [Boolean] whether obj differs from the source on the the non-domain attributes
      def update_saved?(obj, source)
        obj.class.autogenerated_nondomain_attributes.any? do |attr|
          intended = obj.send(attr)
          stored = source.send(attr)
          if intended != stored then
            logger.debug { "Saved #{obj.qp} #{attr} value #{intended} differs from result value #{stored}..." }
          end
        end
      end
      
      # Returns the {MetadataAttributes#updatable_domain_attributes} which are either
      # {AttributeMetadata#cascade_update_to_create?} or have identifiers for all
      # references in the attribute value.
      # 
      # @param (see #update)
      # @return the attributes to include in the update template
      def updatable_domain_attributes(obj)
        obj.class.updatable_domain_attributes.filter do |attr|
          obj.class.attribute_metadata(attr).cascade_update_to_create? or
          obj.send(attr).to_enum.all? { |ref| ref.identifier }
        end
      end

      # @param (see #update)
      def update_object(obj)
        # database identifier is required for update
        if obj.identifier.nil? then
          raise DatabaseError.new("Update target is missing a database identifier: #{obj}")
        end
        
        # if this object is proxied, then delegate to the proxy
        if obj.class.method_defined?(:saver_proxy) then
          return save_with_proxy(obj)
        end
        
        # if a changed dependent is saved with a proxy, then update that dependent first
        proxied = updatable_proxied_dependents(obj)
        unless proxied.empty? then
          proxied.each { |dep| update(dep) }
        end
        
        # update using a template
        tmpl = build_update_template(obj)
        
        # call the caCORE service with an obj update template
        save_with_template(obj, tmpl) { |svc| svc.update(tmpl) }
        # take a snapshot of the updated content
        obj.take_snapshot
      end
      
      # caTissue alert - the conditions for when and how to include a proxied dependent are
      # are intricate and treacherous. So far as can be determined, in the case of a
      # SpecimenPosition proxied by a TransferEventParameters, the sequence is as follows:
      # * If a Specimen without a previous position is updated with a position, then
      #   the update template should not include the target position. Subsequent to the
      #   Specimen update, the TransferEventParameters proxy is created.
      #   This creates a new position in the database as a server side-effect. caRuby
      #   then fetches the new position and merges it into the target position.
      # * If a Specimen with a previous position is updated, then the update template
      #   must reflect the current datbase position state. Therefore, caRuby first
      #   creates the proxy to update the database state.
      # * The TransferEventParameters create must reference a Specimen with the current
      #   database position state, not the new position state.
      # * Update of a Specimen with a current database position must reference a
      #   position which reflects that database state. This is true even if the position
      #   has not changed. The position must be complete and consistent with the database
      #   state. E.g. omitting the position storage container is accepted by caTissue
      #   but corrupts the database side and has adverse delayed effects.
      # * Specimen create (but not auto-generated update) cannot include a position
      #   (although that might have changed in the 1.1.2 release). The target position
      #   must be created via the proxy after the Specimen is created.
      #
      # @param (see #update)
      # @return [<Resource>] the #{ResourceAttributes#proxied_cascaded_attributes} dependents
      #   which are #{Persistable#changed?}
      def updatable_proxied_dependents(obj)
        attrs = obj.class.proxied_cascaded_attributes
        return Array::EMPTY_ARRAY if attrs.empty?
        deps = []
        attrs.each do |attr|
          obj.send(attr).enumerate { |dep| deps << dep if dep.identifier and dep.changed? }
        end
        deps
      end
      
      # @param (see #update)
      def build_update_template(obj)
        @upd_tmpl_bldr.build_template(obj)
      end

      # @param (see #delete)
      # @raise [DatabaseError] if obj does not have an identifier 
      def delete_object(obj)
        # database identifier is required for delete
        if obj.identifier.nil? then
          raise DatabaseError.new("Delete target is missing a database identifier: #{obj}")
        end
        persistence_service(obj).delete_object(obj)
      end

      # Saves the given template built from the given domain object obj. The persistence operation
      # is performed by calling the #persistence_service update or create method on the template.
      # If the template has an identifier, then the service update method is called. Otherwise, the service
      # create method is called on the template. Dependents are saved as well, if necessary.
      #
      # @param obj (see #store)
      # @param [Resource] template the obj template to submit to caCORE
      def save_with_template(obj, template)
        logger.debug { "Saving #{obj.qp} from template:\n#{template.dump}" }
        # call the application service
        # dispatch to the app service
        svc = persistence_service(template)
        result = template.identifier ? svc.update(template) : svc.create(template)
        logger.debug { "Store #{obj.qp} with template #{template.qp} produced caCORE result: #{result}." }
        # sync the result
        sync_saved(obj, result)
      end
      
      def sync_saved(obj, result)
        # delegate to the merge visitor
        src = @svd_mrgr.merge(obj, result)
        # make the saved object persistent, if not already so
        persistify(obj)

        # If saved must be updated, then update recursively.
        # Otherwise, save dependents as needed.
        if update_saved?(obj, src) then
          logger.debug { "Updating saved #{obj} to store unsaved attributes..." }
          # call update_savedect(saved) rather than update(saved) to bypass the redundant update check
          perform(:update, obj) { update_object(obj) }
        else
          # recursively save the dependents
          save_dependents(obj)
        end
      end

      # Saves the given domain object dependents.
      #
      # @param [Resource] obj the owner domain object
      def save_dependents(obj)
        obj.dependents.each { |dep| save_dependent(obj, dep) }
      end
      
      # Saves the given dependent domain object if necessary.
      # Recursively saves the obj dependents as necessary.
      #
      # @param [Resource] obj the dependent domain object to save
      def save_dependent(owner, dep)
        if dep.identifier.nil? then
          logger.debug { "Creating dependent #{dep.qp}..." }
          return create(dep)
        end
        changes = dep.changed_attributes
        logger.debug { "#{owner.qp} dependent #{dep.qp} changed for attributes #{changes.to_series}." } unless changes.empty?
        if changes.any? { |attr| not dep.class.attribute_metadata(attr).dependent? } then
          logger.debug { "Updating changed #{owner.qp} dependent #{dep.qp}..." }
          update(dep)
        else
          save_dependents(dep)
        end
      end
    end
  end
end