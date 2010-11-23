require 'caruby/domain/reference_visitor'

module CaRuby
  # StoreTemplateBuilder creates a template suitable for a create or update database operation.
  class StoreTemplateBuilder
    # Creates a new StoreTemplateBuilder for the given database.
    #
    # @param [Database] database the target database 
    # @yield [ref] the required selector block which determines the attributes copied into the template
    # @yieldparam [Resource] ref the domain object to copy
    def initialize(database)
      @database = database
      unless block_given? then raise ArgumentError.new("StoreTemplateBuilder is missing the required template copy attribute selector block") end
      # the domain attributes to copy
      mgbl = Proc.new { |src, tgt| yield src }
      # copy the reference
      # caTissue alert - must copy all of the non-domain attributes rather than just the identifier,
      # since caTissue auto-generated Specimen update requires the parent collection status. This
      # is the only known occurrence of a referenced object required non-identifier attribute.
      # The copy attributes are parameterized by the top-level save target.
      copier = Proc.new do |src|
        copy = src.copy
        logger.debug { "Store template builder copied #{src.qp} into #{copy}." }
        copy_proxied_save_references(src, copy)
        copy
      end
     # the template copier
      @copy_vstr = CopyVisitor.new(:mergeable => mgbl, :copier => copier) { |src, tgt| savable_cascaded_attributes(src) }
      # the storable prerequisite reference visitor
      @prereq_vstr = ReferenceVisitor.new(:prune_cycle) { |ref| savable_cascaded_attributes(ref) }
    end

    # Returns a new domain object which serves as the argument for obj create or update.
    #
    # This method copies a portion of the obj object graph to a template object.
    # The template object graph consists of copies of obj object graph which are necessary
    # to store obj. The template object graph contains only those references which are
    # essential to the store operation.
    #
    # caCORE alert - +caCORE+ expects the store argument to be carefully prepared prior to
    # the create or update. build_storable_template culls the target object with a template
    # which includes only those references which are necessary for the store to succeed.
    # This method ensures that mandatory independent references exist. Dependent references
    # are included in the template but are not created before submission to +caCORE+ create
    # or update. These fine distinctions are implicit application rules which are explicated
    # in the +caRuby+ application domain class definition using ResourceMetadata methods.
    #
    # caCORE alert - +caCORE+ occasionally induces a stack overflow if a create argument
    # contains a reference cycle. The template fixes this.
    #
    # caCORE alert - +caCORE+ create raises an error if a create argument directly or
    # indirectly references a domain objects without an identifier, even if the
    # reference is not relevant to the create. The template returned by this method elides
    # all non-essential references.
    #
    # caCORE alert - application business logic performs unnecessary verification
    # of uncascaded references as if they were a cascaded create. This can result in
    # an obscure ApplicationException. The server.log stack trace indicates the
    # extraneous verification code. For example, +caTissue+ +NewSpecimenBizLogic.validateStorageContainer+
    # is unnecessarily called on a SpecimenCollectionGroup (SCG) update. SCG does not
    # cascade to Specimen, but caTissue considers the SCG update a Specimen create
    # anyway if the SCG references a Specimen without an identifier. The Specimen
    # business logic then raises an exception when it finds a StorageContainer
    # without an identifier in the Specimen object graph. Therefore, an update must
    # build a storable template which prunes the update object graph to exclude uncascaded
    # objects. These uncascaded objects should be ignored by the application but aren't.
    #
    # @param [Resource] obj the domain object to save
    # @return [Resource] the template to use as the caCORE argument
    def build_template(obj)
      # prepare the object for a store operation
      ensure_storable(obj)
      # copy the cascade hierarchy
      logger.debug { "Building storable template for #{obj.qp}..." }
      tmpl = @copy_vstr.visit(obj)
      logger.debug { "Built #{obj.qp} template #{tmpl.qp} by mapping references #{@copy_vstr.matches.qp}" }
      tmpl
    end

    private
  
    # Ensure that the given domain object obj can be created or updated by setting the identifier for
    # each independent reference in the create template object graph.
    #
    # caCORE alert - +caCORE+ raises an ApplicationException if an independent reference in the create or
    # update argument does not have an identifier. The +caCORE+ server log error is as follows:
    #   java.lang.IllegalArgumentException: id to load is required for loading
    # The server log stack trace indicates a bizlogic line that offers a clue to the offending reference.
    def ensure_storable(obj)
      # Add defaults, which might introduce independent references.
      obj.add_defaults
      # create the prerequisite references if necessary
      prereqs = collect_prerequisites(obj)
      unless prereqs.empty? then
        logger.debug { "Ensuring references for #{obj.qp} exist: #{prereqs.map { |ref| ref.qp }.to_series}..." }
        @database.ensure_exists(prereqs)
        logger.debug { "Prerequisite references for #{obj.qp} exist: #{prereqs.map { |ref| ref }.to_series}." }
      end
      # If obj is being created then add defaults again, since fetched independent references might introduce new defaults.
      obj.add_defaults unless obj.identifier
      # Verify that the object is complete
      obj.validate
    end
      
    # Filters the {ResourceAttributes#updatable_domain_attributes} to exclude
    # the {ResourceAttributes#proxied_cascaded_attributes} whose reference value
    # does not have an identifier. These references will be created by proxy
    # instead.
    #
    # @param [Resource] obj the domain object copied to the update template
    # @return [<Symbol>] the reference attributes to include in the update template
    def savable_cascaded_attributes(obj)
      # always include the unproxied cascaded references
      unproxied = obj.class.unproxied_cascaded_attributes
      if obj.identifier then
        unproxied = unproxied.filter do |attr|
          obj.class.attribute_metadata(attr).cascade_update_to_create? or
          obj.send(attr).to_enum.all? { |ref| ref.identifier }
        end
      end
      
      # Include a proxied reference only if the proxied dependents have an identifier,
      # since those without an identifer are created separately via the proxy.
      proxied = obj.class.proxied_cascaded_attributes.reject do |attr|
        ref = obj.send(attr)
        case ref
        when Enumerable then
           ref.any? { |dep| not dep.identifier }
        when Resource then
          not ref.identifier
        end
      end
      
      proxied.empty? ? unproxied : unproxied + proxied
    end
    
    # Copies proxied references as needed.
    #
    # caTissue alert - even though Specimen save cascades to SpecimenPosition,
    # SpecimenPosition cannot be updated directly. Rather than simply not
    # cascading to the SpecimenPosition, caTissue checks a Specimen save argument
    # to ensure that the SpecimenPosition reflects the current database state
    # rather than the desired cascaded state. Play along with this bizarre
    # mechanism by adding our own bizarre work-around mechanism to copy a
    # proxied reference only if it has an identifier. This works only because
    # another work-around in the #{CaRuby::Database::Writer} updates proxied
    # references via the proxy create before building the update template.
    def copy_proxied_save_references(obj, template)
      return unless obj.identifier
      obj.class.proxied_cascaded_attributes.each do |attr|
        ref = obj.send(attr)
        case ref
        when Enumerable then
          coll = template.send(attr)
          ref.each do |dep|
            copy = copy_proxied_save_reference(obj, attr, template, dep)
            coll << copy if copy
          end
        when Resource then
          copy = copy_proxied_save_reference(obj, attr, template, ref)
          template.set_attribute(attr, copy) if copy
        end
      end
    end
    
    # Copies a proxied reference.
    #
    # @return [Resource, nil] the copy, or nil if no copy is made
    def copy_proxied_save_reference(obj, attribute, template, proxied)
      # only copy an existing proxied
      return unless proxied.identifier
      # the proxied attribute => value hash
      vh = proxied.value_hash
      # map references to either the copied owner or a new copy of the reference
      tvh = vh.transform { |value| Resource === value ? (value == obj ? template : value.copy) : value }
      # the copy with the adjusted values
      copy = proxied.class.new(tvh)
      logger.debug { "Created #{obj.qp} proxied #{attribute} save template copy #{proxied.pp_s}." }
      copy
    end
    
    # Returns the references which must be created in order to store obj.
    def collect_prerequisites(obj)
      prereqs = Set.new
      @prereq_vstr.visit(obj) do |stbl|
        stbl.class.storable_prerequisite_attributes.each do |attr|
          # add qualified prerequisite attribute references
          stbl.send(attr).enumerate do |prereq|
            # add the prerequisite unless it is the object being created, was already created or is
            # in the owner hierarchy 
            unless prereq == obj or prereq.identifier or prereq.owner_ancestor?(obj) then
              prereqs << prereq
            end
          end
        end
      end
      prereqs
    end
  end
end