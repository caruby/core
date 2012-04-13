require 'jinx/resource/reference_visitor'
require 'jinx/resource/copy_visitor'

module CaRuby
  class Database
    module Writer
      # TemplateBuilder creates a template suitable for a database save operation.
      class TemplateBuilder
        # Creates a new TemplateBuilder for the given database. The attributes to merge into
        # the template are determined by the block given to this initializer, filtered as follows:
        # * If the save operation is a create, then exclude the auto-generated attributes.
        # * If the visited object has an identifier, then include only those attributes
        #   which {Domain::Property#cascade_update_to_create?} or have an identifier. 
        #
        # @param [Database] database the target database 
        # @yield [ref] the required selector block which determines which attributes are copied into the template
        # @yieldparam [Jinx::Resource] ref the domain object to copy
        def initialize(database)
          @database = database
          unless block_given? then
            Jinx.fail(ArgumentError, "@{qp} is missing the required template copy attribute selector block")
          end
      
          # the mergeable attributes filter the given block with exclusions
          @mergeable = Proc.new { |ref| mergeable_attributes(ref, yield(ref)) }
          # the savable prerequisite reference visitor
          @prereq_vstr = Jinx::ReferenceVisitor.new(:prune_cycle) { |ref| savable_template_attributes(ref) }
      
          # the savable attributes filter the given block with exclusions
          savable = Proc.new { |ref| savable_attributes(ref, yield(ref)) }
          # the domain attributes to copy is determined by the constructor caller
          # @quirk caTissue must copy all of the non-domain attributes rather than just the identifier,
          # since caTissue auto-generated Specimen update requires the parent collection status. This
          # is the only known occurrence of a referenced object required non-identifier attribute.
          # The copy attributes are parameterized by the top-level save target.
          copier = Proc.new do |src|
            tgt = src.copy
            logger.debug { "Store template builder copied #{src.qp} into #{tgt}." }
            copy_proxied_save_references(src, tgt)
            tgt
          end
          # the template copier
          @copy_vstr = Jinx::CopyVisitor.new(:mergeable => savable, :copier => copier) do |ref|
            savable_template_attributes(ref)
          end
        end

        # Returns a new domain object which serves as the argument for obj create or update.
        #
        # This method copies a portion of the obj object graph to a template object.
        # The template object graph consists of copies of obj object graph which are necessary
        # to store obj. The template object graph contains only those references which are
        # essential to the store operation.
        #
        # @quirk caCORE +caCORE+ expects the store argument to be carefully prepared prior to
        #   the create or update. build_savable_template culls the target object with a template
        #   which includes only those references which are necessary for the store to succeed.
        #   This template builder ensures that mandatory independent references exist. Cascaded
        #   dependent references are included in the template but are not created before submission
        #   to +caCORE+. These reference attribute distinctions are implicit application rules which
        #   are explicated in the +caRuby+ application domain class definition using Metadata
        #   methods.
        #
        # @quirk caCORE +caCORE+ create issues an error if a create argument directly or
        #   indirectly references a non-cascaded domain object without an identifier, even if the
        #   reference is not relevant to the create. The template returned by this method elides
        #   all non-essential references.
        #
        # @quirk caCORE application business logic performs unnecessary verification
        #   of uncascaded references as if they were a cascaded create. This can result in
        #   an obscure ApplicationException. The server.log stack trace indicates the
        #   extraneous verification code. For example, +caTissue+ +NewSpecimenBizLogic.validateStorageContainer+
        #   is unnecessarily called on a SpecimenCollectionGroup (SCG) update. SCG does not
        #   cascade to Specimen, but caTissue considers the SCG update a Specimen create
        #   anyway if the SCG references a Specimen without an identifier. The Specimen
        #   business logic then raises an exception when it finds a StorageContainer
        #   without an identifier in the Specimen object graph. Therefore, an update must
        #   build a savable template which prunes the update object graph to exclude uncascaded
        #   objects. These uncascaded objects should be ignored by the application but aren't.
        #
        # @param [Jinx::Resource] obj the domain object to save
        # @return [Jinx::Resource] the template to use as the caCORE argument
        def build_template(obj, autogenerated=false)
          # set the database operation subject
          @subject = obj
          # prepare the object for a store operation
          ensure_savable(obj)
          # copy the cascade hierarchy
          logger.debug { "Building savable template for #{obj.qp}..." }
          tmpl = @copy_vstr.visit(obj)
          logger.debug { "Built #{obj.qp} template #{tmpl.qp} by mapping references #{@copy_vstr.matches.qp}" }
          tmpl
        end

        private
  
        # Ensure that the given domain object can be created or updated by setting the identifier for
        # each independent reference in the create template object graph.
        #
        # @quirk caCORE +caCORE+ raises an +ApplicationException+ if an independent reference in the
        #    save argument does not have an identifier. The +caCORE+ server log error is as follows:
        #     java.lang.IllegalArgumentException: id to load is required for loading
        #   The server log stack trace indicates a bizlogic line that offers a clue to the offending
        #   reference. caRuby determines which references are independent based on the introspected
        #   metadata and creates them if necessary.
        #
        # @param [Jinx::Resource] obj the object to save
        # @raise [ValidationError] if the object is invalid
        def ensure_savable(obj)
          # Ensure that an update is fetched to complete the object state with any missing references.
          if obj.identifier and not obj.fetched? then
            logger.debug { "Fetching #{obj} prior to building a save template..." }
            @database.find(obj)
          end
          # Fill in the savable references for an update.
          fetch_savable_references(obj) if obj.identifier
          # Add defaults, which might introduce prerequisites.
          obj.add_defaults
          # Fetch or create if necessary the prerequisite references.
          prereqs = collect_prerequisites(obj)
          unless prereqs.empty? then
            logger.debug { "Ensuring references for #{obj.qp} exist: #{prereqs.map { |ref| ref.qp }.to_series}..." }
            @database.ensure_exists(prereqs)
            logger.debug { "Prerequisite references for #{obj.qp} exist: #{prereqs.map { |ref| ref }.to_series}." }
          end
          # Verify that the object is complete
          obj.validate
        end
        
        # Fetches the given update object savable references on demand.
        #
        # @param [Resource] the object to update
        def fetch_savable_references(obj)
          logger.debug { "Fetching #{obj} savable references on demand..." }
          @database.lazy_loader.enable do
            obj.class.savable_template_attributes.each { |pa| obj.send(pa) }
          end
        end
    
        # Returns the attributes to visit in building the template for the given
        # domain object. The visitable attributes consist of the following:
        # * The {Propertied#unproxied_savable_template_attributes} filtered as follows:
        #   * If the database operation is a create, then exclude the cascaded attributes.
        #   * If the given object has an identifier, then exclude the attributes which
        #     have the the :no_cascade_update_to_create flag set.
        # * The {Propertied#proxied_savable_template_attributes} are included if and
        #   only if every referenced object has an identifier, and therefore does not
        #   need to be proxied.
        #
        # @quirk caTissue caTissue ignores some references, e.g. Participant CPR, and auto-generates
        #   the values instead. Therefore, the create template builder excludes these auto-generated
        #   attributes. After the create, the auto-generated references are merged into the created
        #   object graph and the references are updated if necessary.
        #
        # @param [Jinx::Resource] obj the domain object copied to the update template
        # @return [<Symbol>] the reference attributes to include in the update template
        def savable_template_attributes(obj)
          # The starting set of candidate attributes is the unproxied cascaded references.
          unproxied = savable_attributes(obj, obj.class.unproxied_savable_template_attributes)
          # The proxied attributes to save.
          proxied = savable_proxied_attributes(obj)
          # The combined set of savable attributes
          if proxied.empty? then
            # This is almost always the code path.
            unproxied
          else
            sas = unproxied.to_set.merge(proxied)
            obj.class.domain_attributes.compose { |prop| sas.include?(prop.attribute) }
          end
        end
    
        # Filters the given attributes, if necessary, to exclude attributes as follows:
        # * If the save operation is a create, then exclude the
        #   {Domain::Property#autogenerated?} attributes.
        #
        # @param [Jinx::Resource] obj the visited domain object
        # @param [Propertied::Filter] the savable attribute filter
        # @return [Propertied::Filter] the composed attribute filter
        def mergeable_attributes(obj, attributes)
          # If this is an update, then there is no filter on the given attributes.
          return attributes if @subject.identifier
          # This is a create: ignore the optional auto-generated attributes.
          mas = obj.mandatory_attributes.to_set
          attributes.compose { |pa| mas.include?(pa.to_sym) or not pa.autogenerated? }
        end
        
        # Composes the given attributes, if necessary, to exclude attributes as follows:
        # * If the save operation is a create, then exclude the auto-generated attributes
        #   and independent attributes with unsaved references.
        # * If the visited object has an identifier, then include only those attributes
        #   which {Domain::Property#cascade_update_to_create?} or have an identifier. 
        #
        # @param (see #mergeable_attributes)
        # @return (see #mergeable_attributes)
        def savable_attributes(obj, attributes)
          mgbl = mergeable_attributes(obj, attributes)
          if obj.identifier.nil? then
            mgbl.compose do |prop|
              not bidirectional_unsaved_independent_collection?(obj, prop)
            end
          else
            # The currently visited object is an update: include attributes which
            # either cascade update to create or have saved references.
            mgbl.compose do |prop|
              prop.cascade_update_to_create? or Persistable.saved?(obj.send(prop.attribute))
            end
          end
        end
        
        def bidirectional_unsaved_independent_collection?(obj, property)
          property.collection? and
            property.independent? and
            property.bidirectional? and
            Persistable.unsaved?(obj.send(property.attribute))
        end
   
        # Returns the proxied attributes to save. A proxied attribute is included only if the proxied
        # dependents have an identifier, since those without an identifer are created separately via
        # the proxy.
        #
        # @param [Jinx::Resource] obj the visited domain object
        # @return [Jinx::AttributeEnumerator] the proxied cascaded attributes with an unsaved reference
        def savable_proxied_attributes(obj)
          # Include a proxied reference only if the proxied dependents have an identifier,
          # since those without an identifer are created separately via the proxy.
          obj.class.proxied_savable_template_attributes.filter do |pa|
            ref = obj.send(pa)
            case ref
              when Enumerable then ref.all? { |dep| dep.identifier }
              when Jinx::Resource then ref.identifier
            end
          end
        end
    
        # Copies proxied references as needed.
        #
        # @quirk caTissue even though Specimen save cascades to SpecimenPosition,
        #   SpecimenPosition cannot be updated directly. Rather than simply not
        #   cascading to the SpecimenPosition, caTissue checks a Specimen save argument
        #   to ensure that the SpecimenPosition reflects the current database state
        #   rather than the desired cascaded state. Play along with this bizarre
        #   mechanism by adding our own bizarre work-around mechanism to copy a
        #   proxied reference only if it has an identifier. This works only because
        #   another work-around in the #{Writer} updates proxied
        #   references via the proxy create before building the update template.
        def copy_proxied_save_references(obj, template)
          return unless obj.identifier
          obj.class.proxied_savable_template_attributes.each do |pa|
            # the proxy source
            ref = obj.send(pa)
            case ref
              when Enumerable then
                # recurse on the source collection
                coll = template.send(pa)
                ref.each do |dep|
                  copy = copy_proxied_save_reference(obj, pa, template, dep)
                  coll << copy if copy
                end
              when Jinx::Resource then
                # copy the source
                copy = copy_proxied_save_reference(obj, pa, template, ref)
                # set the attribute to the copy
                template.set_property_value(pa, copy) if copy
            end
          end
        end
    
        # Copies a proxied reference.
        #
        # @return [Jinx::Resource, nil] the copy, or nil if no copy is made
        def copy_proxied_save_reference(obj, attribute, template, proxied)
          # only copy an existing proxied
          return unless proxied.identifier
          # the proxied attribute => value hash
          vh = proxied.value_hash
          # map references to either the copied owner or a new copy of the reference
          tvh = vh.transform_value { |v| Jinx::Resource === v ? (v == obj ? template : v.copy) : v }
          # the copy with the adjusted values
          copy = proxied.class.new.merge_attributes(tvh)
          logger.debug { "Created #{obj.qp} proxied #{attribute} save template copy #{proxied.pp_s}." }
          copy
        end
    
        # A directly or indirectly referenced object is a target object save prerequisite if
        # none of the following is true:
        # * it is cascaded and will be created when the target is saved
        # * it is a bidirectional unsaved independent collection reference
        # * it is the target object
        # * it has an identifier
        # * it is in an immediate or recursive dependent of the target object
        # * the current save operation is in the context of creating the referenced object
        #
        # @param [Jinx::Resource] obj the domain object to save
        # @return [<Jinx::Resource>] the references which must be created in order to store the object
        def collect_prerequisites(obj)
          prereqs = Set.new
          # visit the cascaded attributes
          @prereq_vstr.visit(obj) do |pref|
            # Check each mergeable attribute for prerequisites. The mergeable attributes includes
            # both cascaded and independent attributes. The selection block filters for independent
            # domain objects which don't have an identifier.
            @mergeable.call(pref).each_pair do |ma, mp|
              # Cascaded attributes are not prerequisite, since they are created when the owner is
              # created. The exception is if the owner will be updated but the dependent will not
              # be created upon owner update and the dependent does not reference the owner.
              # In that case, create the dependent before saving the owner. This ensures that the
              # owner saves the reference to the new dependent.
              # 
              # Note that each non-prerequisite cascaded reference is still visited in order to ensure
              # that each independent object referenced by a cascaded reference is recognized as a
              # candidate prerequisite.
              if mp.cascaded? then
                unless pref.identifier.nil? or mp.inverse_property or mp.cascade_update_to_create? then
                  pref.send(ma).enumerate do |mref|
                    prereqs << mref if mref != obj and mref.identifier.nil?
                  end
                end
              elsif not bidirectional_unsaved_independent_collection?(pref, mp) then
                # add qualified prerequisite attribute references
                pref.send(ma).enumerate do |mref|
                  # Add each unsaved reference that is not a direct or indirect dependent.
                  unless mref == obj or mref.identifier or mref.owner_ancestor?(obj) then
                    prereqs << mref
                  end
                end
              end
            end
          end
          prereqs
        end
      end
    end
  end
end