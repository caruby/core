require 'caruby/util/collection'
require 'caruby/util/pretty_print'
require 'caruby/domain/reference_visitor'
require 'caruby/database/saved_matcher'
require 'caruby/database/store_template_builder'

module CaRuby
  class Database
    # Database store operation mixin.
    module Writer
      # Adds store capability to this Database.
      def initialize
        super
        @ftchd_vstr = ReferenceVisitor.new { |tgt| tgt.class.fetched_domain_attributes }
        @cr_tmpl_bldr = StoreTemplateBuilder.new(self) { |ref| creatable_domain_attributes(ref) }
        @upd_tmpl_bldr = StoreTemplateBuilder.new(self) { |ref| updatable_domain_attributes(ref) }
        # the save result => argument reference matcher
        svd_mtchr = SavedMatcher.new
        # the save (result, argument) synchronization visitor
        @svd_sync_vstr = MatchVisitor.new(:matcher => svd_mtchr) { |ref| ref.class.dependent_attributes }
        # the attributes to merge from the save result
        mgbl = Proc.new { |ref| ref.class.domain_attributes } 
        # the save result => argument merge visitor
        @svd_mrg_vstr = MergeVisitor.new(:matcher => svd_mtchr, :mergeable => mgbl) { |ref| ref.class.dependent_attributes }
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
        logger.debug { "Saving #{obj}..." }
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

      private
      
      # Returns whether there is already the given object operation in progress that is not in the scope of
      # an operation performed on a dependent obj owner, i.e. a second obj save operation of the same type
      # is only allowed if the obj operation was delegated to an owner save which in turn saves the dependent
      # obj.
      #
      # @param [Resource] obj the domain object to save
      # @param [Symbol] operation the +:create+ or +:update+ save operation
      # @return [Boolean] whether the save operation is redundant
      def recursive_save?(obj, operation)
        @operations.any? { |op| op.type == operation and op.subject == obj } and
          not obj.owner_ancestor?(@operations.last.subject)
      end
      
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
          # A dependent is created by saving the owner.
          # Otherwise, create the object from a template.
          owner = cascaded_owner(obj)
          result = create_dependent(owner, obj) if owner
          result ||= create_from_template(obj)
          if result.nil? then
            raise DatabaseError.new("#{obj.class.qp} is not creatable in context #{print_operations}")
          end
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
      def create_dependent(owner, dep)
        if owner.identifier.nil? then
          logger.debug { "Adding #{owner.qp} dependent #{dep.qp} defaults..." }
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
          refs = obj.references.reject { |ref| ref.identifier }
          logger.debug { "Ensuring that created #{obj.qp} references exist: #{refs.qp}..." } unless refs.empty?
          refs.each { |ref| ensure_exists(ref) }
        end
        
        obj
      end
      
      # @param (see #create)
      # @return (see #build_save_template)
      def build_create_template(obj)
        build_save_template(obj, @cr_tmpl_bldr)
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
      
      # Returns the {MetadataAttributes#creatable_domain_attributes} which are not contravened by a
      # one-to-one independent pending create.
      # 
      # @param (see #create)
      # @return [<Symbol>] the attributes to include in the create template
      def creatable_domain_attributes(obj)
        # filter the creatable attributes
        obj.class.creatable_domain_attributes.compose do |attr_md|
          if exclude_pending_create_attribute?(obj, attr_md) then
            # Avoid printing duplicate log message.
            if obj != @cr_dom_attr_log_obj then
              logger.debug { "Excluded #{obj.qp} #{attr_md} in the create template since it references a 1:1 bidirectional independent pending create." }
              @cr_dom_attr_log_obj = obj
            end
            false
          else
            true
          end
        end
      end
      
      # Returns whether the given creatable domain attribute with value obj satisfies
      # each of the following conditions:
      # * the attribute is {AttributeMetadata#independent?}
      # * the attribute is not an {AttributeMetadata#owner?}
      # * the obj value is unsaved
      # * the attribute is not mandatory
      # * the attribute references a {#pending_create?} save context.
      #
      # @param obj (see #create)
      # @param [AttributeMetadata] attr_md candidate attribute metadata
      # @return [Boolean] whether the attribute should not be included in the create template
      def exclude_pending_create_attribute?(obj, attr_md)
        attr_md.independent? and
          not attr_md.owner? and
          obj.identifier.nil? and
          not obj.mandatory_attributes.include?(attr_md.to_sym) and
          exclude_pending_create_value?(obj.send(attr_md.to_sym))
      end
      
      # @param [Resource, <Resource>, nil] value the referenced value
      # @return [Boolean] whether the value includes a {#pending_create?} save context object
      def exclude_pending_create_value?(value)
        return false if value.nil?
        if Enumerable === value then
           value.any? { |ref| exclude_pending_create_value?(ref) }
        else
          value.identifier.nil? and pending_create?(value)
        end
      end
      
      # @param [Resource] obj the object to check
      # @return [Boolean] whether the penultimate create operation is on the object
      def pending_create?(obj)
        op = penultimate_create_operation
        op and op.subject == obj
      end
      
      # @return [Operation] the create operation which scopes the innermost create operation
      def penultimate_create_operation
        @operations.reverse_each { |op| return op if op.type == :create and op != @operations.last }
        nil
      end
      
      # Returns the {MetadataAttributes#updatable_domain_attributes}.
      # 
      # @param (see #update)
      # @return the attributes to include in the update template
      def updatable_domain_attributes(obj)
        obj.class.updatable_domain_attributes
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
        
        # update a cascaded dependent by updating the owner
        owner = cascaded_owner(obj)
        result = update_dependent(owner, obj) if owner
        # if not cascaded, then update directly with a template
        result ||= create_from_template(obj)
        
        # update using a template
        tmpl = build_update_template(obj)
        
        # call the caCORE service with an obj update template
        save_with_template(obj, tmpl) { |svc| svc.update(tmpl) }
        # take a snapshot of the updated content
        obj.take_snapshot
      end
      
      # Returns the owner that can cascade update to the given object.
      # The owner is the #{Resource#effective_owner_attribute_metadata} value
      # for which the owner attribute {AttributeMetadata#inverse_attribute_metadata}
      # is {AttributeMetadata#cascaded?}.
      # 
      # @param [Resource] obj the domain object to update
      # @return [Resource, nil] the owner which can cascade an update to the object, or nil if none
      # @raise [DatabaseError] if the domain object is a cascaded dependent but does not have an owner
      def cascaded_owner(obj)
        return unless obj.class.cascaded_dependent?
        # the owner attribute
        oattr = obj.effective_owner_attribute
        if oattr.nil? then raise DatabaseError.new("Dependent #{obj} does not have an owner") end
        dep_md = obj.class.attribute_metadata(oattr).inverse_attribute_metadata
        if dep_md and dep_md.cascaded? then
          obj.send(oattr)
        end
      end
      
      def update_dependent(owner, obj)
        logger.debug { "Updating #{obj} by saving the owner #{owner}..." }
        update(owner)
      end
      
      def update_from_template(obj)
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
      # @return [<Resource>] the #{ResourceAttributes#proxied_save_template_attributes} dependents
      #   which are #{Persistable#changed?}
      def updatable_proxied_dependents(obj)
        attrs = obj.class.proxied_save_template_attributes
        return Array::EMPTY_ARRAY if attrs.empty?
        deps = []
        attrs.each do |attr|
          obj.send(attr).enumerate { |dep| deps << dep if dep.identifier and dep.changed? }
        end
        deps
      end
      
      # @param (see #update)
      # @return (see #build_save_template)
      def build_update_template(obj)
        build_save_template(obj, @upd_tmpl_bldr)
      end
      
      # @param obj (see #save)
      # @param [StoreTemplateBuilder] builder the builder to use
      # @return [Resource] the template to use as the save argument
      def build_save_template(obj, builder)
        builder.build_template(obj)
      end

      # @param (see #delete)
      # @raise [DatabaseError] if obj does not have an identifier 
      def delete_object(obj)
        # database identifier is required for delete
        if obj.identifier.nil? then
          raise DatabaseError.new("Delete target is missing a database identifier: #{obj}")
        end
        persistence_service(obj.class).delete_object(obj)
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
        # dispatch to the application service
        result = submit_save_template(obj, template)
        # sync the result
        sync_saved(obj, result)
      end
      
      # Dispatches the given template to the application service.
      #
      # @param (see #save_with_template)
      def submit_save_template(obj, template)
        svc = persistence_service(template.class)
        result = template.identifier ? svc.update(template) : svc.create(template)
        logger.debug { "Store #{obj.qp} with template #{template.qp} produced caCORE result: #{result}." }
        result
      end
      
      # Synchronizes the content of the given saved domain object and the save result source as follows:
      # 1. The save result source is first synchronized with the database content as necessary.
      # 2. Then the source is merged into the target.
      # 3. If the target must be resaved based on the call to {#update_saved?}, then the source
      #    result is resaved.
      # 4. Each target dependent which differs from the corresponding source dependent is saved.
      #
      # @param [Resource] target the saved domain object
      # @param [Resource] source the caCORE save result
      def sync_saved(target, source)
        # clear the toxic source attributes
        detoxify(source)
        # sync the save result source with the database
        sync_saved_result_with_database(source, target)
        # merge the source into the target
        merge_saved(target, source)

        # If saved must be updated, then update recursively.
        # Otherwise, save dependents as needed.
        if update_saved?(target, source) then
          logger.debug { "Updating saved #{target} to store unsaved attributes..." }
          # call update_object(saved) rather than update(saved) to bypass the redundant update check
          perform(:update, target) { update_object(target) }
        else
          # recursively save the dependents
          save_changed_dependents(target)
        end
      end
      
      # Synchronizes the given saved target result source with the database content.
      # The source is synchronized by {#sync_save_result}.
      #
      # @param (see #sync_saved)
      def sync_saved_result_with_database(source, target)
        @svd_sync_vstr.visit(source, target) { |src, tgt| sync_save_result(src, tgt) }
      end
      
      # Merges the database content into the given saved domain object.
      # Dependents are merged recursively.
      #
      # caTissue alert - the auto-generated references are not necessarily valid, e.g. the auto-generated
      # SpecimenRequirement characteristics tissue site is nil rather than the default 'Not Specified'.
      # This results in an obscure downstream error when creating an CPR which auto-generates a SCG
      # which auto-generates a Specimen which copies the invalid characteristics. The work-around for
      # this bug is to add defaults to auto-generated references. Then, if the content differs from
      # the database, the difference induces an update of the reference.
      #
      # @param (see #sync_saved)
      # @return [Resource] the merged target object
      def merge_saved(target, source)
        logger.debug { "Merging saved result #{source} into saved #{target.qp}..." }
        # Update each saved reference snapshot to reflect the database state and add a lazy loader if necessary.
        @svd_mrg_vstr.visit(source, target) do |src, tgt|
          # capture the id
          prev_id = tgt.identifier
          persistify_object(tgt, src)
          # if tgt is an auto-generated reference, then add defaults
          if target != tgt and prev_id.nil? then tgt.add_defaults end
        end
        logger.debug { "Merged saved result #{source} into saved #{target.qp}." }
      end
      
      # Synchronizes the given save result source object to reflect the database content, as follows:
      # * If the save result has autogenerated non-domain attributes, then the source is refetched.
      # * Each of the dependent {#synchronization_attributes} is fetched.
      # * Inverses are set consistently within the save result object graph.
      #
      # @param (see #sync_saved)
      def sync_save_result(source, target)
        # Bail if the result is the same as the source, as occurs, e.g., with caTissue annotations.
        return if source == target
        # If the target was created, then refetch and merge the source if necessary to reflect auto-generated
        # non-domain attribute values.
       if target.identifier.nil? then sync_created_result_object(source) end
        # If there are auto-generated attributes, then merge them into the save result.
        sync_save_result_references(source, target)
        # Set inverses consistently in the source object graph
        set_inverses(source)
      end
      
      # Refetches the given create result source if there are any {ResourceAttributes#autogenerated_nondomain_attributes}
      # which must be fetched to reflect the database state.
      #
      # @param source (see #sync_saved)
      def sync_created_result_object(source)
        attrs = source.class.autogenerated_nondomain_attributes
        return if attrs.empty?
        logger.debug { "Refetch #{source} to reflect auto-generated database content for attributes #{attrs.to_series}..." }
        find(source)
      end
      
      # Fetches the {#synchronization_attributes} into the given target save result source.
      #
      # @param (see #sync_saved)
      def sync_save_result_references(source, target)
        attrs = synchronization_attributes(source, target)
        return if attrs.empty?
        logger.debug { "Fetching the saved #{target.qp} attributes #{attrs.to_series} into save result #{source.qp}..." }
        attrs.each { |attr| sync_save_result_attribute(source, attr) }
        logger.debug { "Fetched the saved #{target.qp} attributes #{attrs.to_series} into the save result #{source.qp}." }
      end
      
      # @see #sync_save_result_references
      def sync_save_result_attribute(source, attribute)
        # fetch the value
        fetched = fetch_association(source, attribute)
        # set the attribute
        source.set_attribute(attribute, fetched)
      end
      
      # Returns the saved target attributes which must be fetched to reflect the database content, consisting
      # of the following:
      # * {Persistable#saved_fetch_attributes}
      # * {ResourceAttributes#domain_attributes} which include a source reference without an identifier
      #
      # @param (see #sync_saved)
      # @return [<Symbol>] the attributes which must be fetched
      def synchronization_attributes(source, target)
        # the target save operation
        op = @operations.last
        # the attributes to fetch
        attrs = target.saved_fetch_attributes(op).to_set
        # the pending create, if any
        pndg_op = penultimate_create_operation
        pndg = pndg_op.subject if pndg_op
        # add in the domain attributes whose identifier was not set in the result
        source.class.saved_domain_attributes.select do |attr|
          srcval = source.send(attr)
          tgtval = target.send(attr)
          if Persistable.unsaved?(srcval) then
            logger.debug { "Fetching save result #{source.qp} #{attr} since a referenced object identifier was not set in the result..." }
            attrs << attr
          elsif srcval.nil_or_empty? and Persistable.unsaved?(tgtval) and tgtval != pndg then
            logger.debug { "Fetching save result #{source.qp} #{attr} since the target #{target.qp} value #{tgtval.qp} is missing an identifier..." }
            attrs << attr
          end
        end
        attrs
      end
      
      # Saves the given domain object dependents.
      #
      # @param [Resource] obj the owner domain object
      def save_changed_dependents(obj)
        obj.class.dependent_attributes.each do |attr|
          deps = obj.send(attr).to_enum
          logger.debug { "Saving the #{obj} #{attr} dependents #{deps.qp} which have changed..." } unless deps.empty?
          deps.each { |dep| save_dependent_if_changed(obj, attr, dep) }
        end
      end
      
      # Saves the given dependent domain object if necessary.
      # Recursively saves the obj dependents as necessary.
      #
      # @param [Resource] owner the dependent owner
      # @param [Symbol] attribute the dependent attribute
      # @param [Resource] dependent the dependent to save
      def save_dependent_if_changed(owner, attribute, dependent)
        if dependent.identifier.nil? then
          logger.debug { "Creating #{owner.qp} #{attribute} dependent #{dependent.qp}..." }
          return create(dependent)
        end
        changes = dependent.changed_attributes
        logger.debug { "#{owner.qp} #{attribute} dependent #{dependent.qp} changed for attributes #{changes.to_series}." } unless changes.empty?
        if changes.any? { |attr| not dependent.class.attribute_metadata(attr).dependent? } then
          # the owner save operation
          op = operations.last
          # The dependent is auto-generated if the owner was created or auto-generated and
          # the dependent attribute is auto-generated.
          attr_md = owner.class.attribute_metadata(attribute)
          ag = (op.type == :create or op.autogenerated?) && attr_md.autogenerated?
          logger.debug { "Updating the changed #{owner.qp} #{attribute} dependent #{dependent.qp}..." }
          if ag then
            logger.debug { "Adding defaults to the auto-generated #{owner.qp} #{attribute} dependent #{dependent.qp}..." }
            dependent.add_defaults_autogenerated
          end
          update_changed_dependent(owner, attribute, dependent, ag)
        else
          save_changed_dependents(dependent)
        end
      end
      
      # Updates the given dependent.
      #
      # @param (see #save_dependent_if_changed)
      def update_changed_dependent(owner, attribute, dependent, autogenerated)
        perform(:update, dependent, :autogenerated => autogenerated) { update_object(dependent) }
      end
    end
  end
end