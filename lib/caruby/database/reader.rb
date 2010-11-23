require 'caruby/util/collection'
require 'caruby/util/cache'
require 'caruby/util/pretty_print'
require 'caruby/domain/reference_visitor'
require 'caruby/database/fetched_matcher'
require 'caruby/database/search_template_builder'

module CaRuby
  class Database
    # Database query operation mixin.
    module Reader
      # Adds query capability to this Database.
      def initialize
        super
        # the demand loader
        @lazy_loader = lambda { |obj, attr| lazy_load(obj, attr) }
        # the query template builder
        @srch_tmpl_bldr = SearchTemplateBuilder.new(self)
        # the fetch result matcher
        @matcher = FetchedMatcher.new

        # cache not yet tested - TODO: test and replace copier below with cacher
        # the fetched object cacher
        #cacher = Proc.new { |src| @cache[src] }

        # the fetched copier
        copier = Proc.new do |src|
          copy = src.copy
          logger.debug { "Fetched #{src.qp} copied to #{copy.qp}." }
          copy
        end
        # visitor that merges the fetched object graph
        @ftchd_vstr = ReferenceVisitor.new { |tgt| tgt.class.fetched_domain_attributes }
        @ftchd_mrg_vstr = MergeVisitor.new(:matcher => @matcher, :copier => copier) { |src, tgt| tgt.class.fetched_domain_attributes }
        # visitor that copies the fetched object graph
        @detoxifier = CopyVisitor.new(:copier => copier) { |src, tgt| src.class.fetched_domain_attributes }
      end

      # Returns an array of objects matching the specified query template and attribute path.
      # The obj_or_hql argument is either a domain object template or a
      # Hibernate[http://www.hibernate.org/docs.html] HQL statement. If obj_or_hql
      # is a String, then the HQL statement String is executed.
      #
      # Otherwise, the query condition is determined by the values set in the template.
      # The non-nil {ResourceAttributes#searchable_attributes} are used in the query.
      #
      # The optional path arguments are attribute symbols from the template to the
      # destination class, e.g.:
      #   query(study, :registration, :participant)
      # returns study registration participants.
      #
      # Unlike caCORE, the query result reflects the database state, i.e. calling an attribute
      # accessor method on a query result object returns the database value, e.g.:
      #   query(study, :registration).first.participant
      # has the same content as:
      #   query(study, :registration, :participant).first
      #
      # By contrast, caCORE API search result property access, by design, fails with an
      # obscure exception when the property is not lazy-loaded in Hibernate.
      #
      # @param [Resource, String] obj_or_hql the domain object or HQL to query
      # @param [<Attribute>] path the attribute path to search
      # @return [<Resource>] the domain objects which match the query
      def query(obj_or_hql, *path)
        # the detoxified caCORE query result
        result = query_safe(obj_or_hql, *path)
        # enable change tracking and lazy-loading
        persistify(result)
      end

      # Queries the given obj_or_hql as described in {#query} and makes a detoxified copy of the
      # toxic caCORE search result.
      #
      # caCORE alert - The query result consists of new domain objects whose content is copied
      # from the caBIG application search result. The caBIG result is Hibernate-enhanced but
      # sessionless. This result contains toxic broken objects whose access methods fail.
      # Therefore, this method sanitizes the toxic caBIG result to reflect the persistent state
      # of the domain objects. Persistent references are loaded on demand from the database if
      # necessary.
      #
      # @param (see #query)
      # @return (see #query)
      def query_safe(obj_or_hql, *path)
        # the caCORE search result
        toxic = query_toxic(obj_or_hql, *path)
        logger.debug { "Copying caCORE query toxic #{toxic.qp}..." } unless toxic.empty?
        # detoxify the toxic caCORE result
        detoxify(toxic)
      end

      # Queries the given obj_or_hql as described in {#query} and returns the toxic caCORE search result.
      #
      # @param (see #query)
      # @return (see #query)
      def query_toxic(obj_or_hql, *path)
        # the attribute path as a string
        path_s = path.join('.') unless path.empty?
        # guard against recursive call back into the same operation
        if query_redundant?(obj_or_hql, path_s) then
          raise DatabaseError.new("Query #{obj_or_hql.qp} #{path_s} recursively called in context #{print_operations}")
        end
        # perform the query
        perform(:query, obj_or_hql, path_s) { query_with_path(obj_or_hql, path) }
      end

      # Fetches the given domain object from the database.
      # Only secondary key attributes are used in the match.
      # If no secondary key is defined for the object's class, then this method returns nil.
      # The {#query} method is used to fetch records on non-secondary key attributes.
      #
      # If the :create option is set, then this method creates an object if the
      # find is unsuccessful.
      #
      # @param [Resource] obj the domain object to find
      # @param [Hash, Symbol] opts the find options
      # @option opts [Boolean] :create whether to create the object if it is not found
      # @return [Resource, nil] the domain object if found, nil otherwise
      # @raise [DatabaseError] if obj is not a domain object or more than object
      #   matches the obj attribute values
      def find(obj, opts=nil)
        return if obj.nil?
        perform(:find, obj) do
          if find_object(obj) then
            logger.info { "Found #{obj}." }
            obj
          else
            logger.info { "#{obj.qp} not found." }
            if Options.get(:create, opts) then create(obj) end
          end
        end
      end

      # Returns whether domain object obj has a database identifier or exists in the database.
      # This method fetches obj from the database if necessary.
      # If obj is a domain object collection, then returns whether each item in the collection exists.
      def exists?(obj)
        if obj.nil? then
          false
        elsif obj.collection? then
          obj.all? { |item| exists?(item) }
        else
          obj.identifier or find(obj)
        end
      end

      private

      RESULT_PRINTER = PrintWrapper.new { |obj| obj.qp }
      
      def lazy_load(obj, attribute)
        value = fetch_association(obj, attribute)
        # add a lazy loader and snapshot to each fetched reference
        persistify(value) if value
      end

      def query_redundant?(obj_or_hql, path)
        @operations.detect { |op| op.type == :query and query_subject_redundant?(op.subject, obj_or_hql) and op.attribute == path }
      end

      def query_subject_redundant?(s1, s2)
        s1 == s2 or (Resource === s1 and Resource === s2 and s1.identifier and s1.identifier == s2.identifier)
      end

      # @return an array of objects matching the given query template and path
      # @see #query
      def query_with_path(obj_or_hql, path)
        # the last attribute in the path, if any
        attribute = path.pop
        # if there is more than attribute to follow, then query up to the last attribute and
        # gather the results of querying on those penultimate result objects with the last
        # attribute as the path
        unless path.empty? then
          if attribute.nil? then raise DatabaseError.new("Query path includes empty attribute: #{path.join('.')}.nil") end
          logger.debug { "Decomposing query on #{obj_or_hql} with path #{path.join('.')}.#{attribute} into query on #{path.join('.')} followed by #{attribute}..." }
          return query_safe(obj_or_hql, *path).map { |parent| query_toxic(parent, attribute) }.flatten
        end
        # perform the attribute query
        query_with_attribute(obj_or_hql, attribute)
      end

      # Returns an array of objects matching the given query template and optional attribute.
      # @see #query
      def query_with_attribute(obj_or_hql, attribute=nil)
        toxic = if String === obj_or_hql then
          hql = obj_or_hql
          # if there is an attribute, then compose the hql query with an attribute query
          if attribute then
            query_safe(hql).map { |parent| query_toxic(parent, attribute) }.flatten
          else
            query_hql(hql)
          end
        else
          obj = obj_or_hql
          query_object(obj, attribute)
        end
        logger.debug { print_query_result(toxic) }
        toxic
      end

      # caCORE alert - post-process the +caCORE+ search result to fix the following problem:
      # * de-referencing a search result domain object raises a Hibernate missing session error
      #
      # caCORE alert - The caCORE search result does not set the obvious inverse attributes,
      # e.g. the children fetched with a parent do not have the children inverse parent attribute
      # set to the parent. Rather, it is a toxic caCORE reference which must be purged. This
      # leaves an empty reference which must be lazy-loaded, which is inefficient and inconsistent.
      # This situation is rectified in this detoxify method by setting the dependent owner
      # attribute to the fetched owner in the detoxification {ReferenceVisitor} copy-match-merge.
      #
      # This method copies each result domain object into a new object of the same type.
      # The copy nondomain attribute values are set to the fetched object values.
      # The copy fetched reference attribute values are set to a copy of the result references.
      #
      # Returns the detoxified copy.
      def detoxify(toxic)
        return toxic.map { |obj| detoxify(obj) } if toxic.collection?
        @detoxifier.visit(toxic)
      end

      # Merges fetched into target. The fetched references are recursively merged.
      #
      # @param [Resource] target the domain object find argument
      # @param [Resource] source the fetched domain object result
      def merge_fetched(target, source)
        @ftchd_mrg_vstr.visit(target, source) { |src, tgt| tgt.copy_volatile_attributes(src) }
      end

      def print_query_result(result)
        count_s = 'result object'.quantify(result.size)
        result_printer = result.wrap { |item| RESULT_PRINTER.wrap(item) }
        "Persistence service query returned #{count_s}: #{result_printer.pp_s(:single_line)}"
      end

      def query_hql(hql)
        java_name = hql[/from\s+(\S+)/i, 1]
        raise DatabaseError.new("Could not determine target type from HQL: #{hql}") if java_name.nil?
        target = Class.to_ruby(java_name)
        service = persistence_service(target)
        service.query(hql)
      end

      # Returns an array of objects fetched from the database which matches
      # a template and follows the given optional domain attribute, if present.
      #
      # The search template is built by {SearchTemplateBuilder#build_template}.
      # If a template could not be built and obj is dependent, then this method
      # queries the obj owner with a dependent filter.
      #
      # caCORE alert - Bug #79 - API search with only id returns entire table.
      # Work around this bug by issuing a HQL query instead.
      #
      # @param [Resource] obj the query template object
      # @param [Symbol, nil] attribute the optional attribute to fetch
      # @return [<Resource>] the query result
      def query_object(obj, attribute=nil)
       if invertible_query?(obj, attribute) then
          # caCORE alert - search with attribute ignores id (cf. caTissue Bug #79);
          # inverted query is safer if possible
          query_with_inverted_reference(obj, attribute)
        elsif obj.identifier then
          query_on_identifier(obj, attribute)
        else
          tmpl = @srch_tmpl_bldr.build_template(obj)
          return Array::EMPTY_ARRAY if tmpl.nil?
          query_on_template(tmpl, attribute)
        end
      end

      # Returns an array of objects fetched from the database which matches
      # the given template and follows the given optional domain attribute.
      def query_on_template(template, attribute=nil)
        target = attribute ? template.class.domain_type(attribute) : template.class
        service = persistence_service(target)
        attribute ? service.query(template, attribute) : service.query(template)
      end

      # Queries the given obj and attribute by issuing a HQL query with an identifier condition.
      def query_on_identifier(obj, attribute)
        # the source class
        source = obj.class.java_class.name
        # the source alias is the lower-case first letter of the source class name without package prefix
        sa = source[/([[:alnum:]])[[:alnum:]]*$/, 1].downcase
        # the HQL condition
        hql = "from #{source} #{sa} where #{sa}.id = #{obj.identifier}"

        # the join attribute property
        if attribute then
          pd = obj.class.attribute_metadata(attribute).property_descriptor
          hql.insert(0, "select #{sa}.#{pd.name} ")
        end
        logger.debug { "Querying on #{obj.qp} #{attribute} using HQL #{hql}..." }

        query_hql(hql)
      end

      # Returns whether the query specified by obj and attribute can be inverted as a query
      # on a template of type attribute which references obj. This condition holds if obj
      # has a key and attribute is a non-abstract reference with a searchable inverse.
      def invertible_query?(obj, attribute)
        return false if attribute.nil?
        attr_md = obj.class.attribute_metadata(attribute)
        return false if attr_md.type.abstract?
        inv_md = attr_md.inverse_attribute_metadata
        inv_md and inv_md.searchable? and finder_parameters(obj)
      end

      # Queries the given obj attribute by querying an attribute type template which references obj.
      def query_with_inverted_reference(obj, attribute)
        attr_md = obj.class.attribute_metadata(attribute)
        logger.debug { "Querying on #{obj.qp} #{attribute} by inverting the query as a #{attr_md.type.qp} #{attr_md.inverse} reference query..." }
        # an obj template
        ref = finder_template(obj)
        # the attribute inverse query template
        tmpl = attr_md.type.new
        # the inverse attribute
        inv_md = tmpl.class.attribute_metadata(attr_md.inverse)
        # the Java property writer to set the tmpl inverse to ref.
        # use the property writer rather than the attribute writer in order to curtail automatically
        # adding tmpl to the ref attribute value when the inv_md attribute is set to ref.
        # caCORE alert - caCORE query relies on a lack of inverse integrity, since caCORE search
        # enters an infinite loop upon encountering an object graph cycle.
        writer = inv_md.property_accessors.last
        # parameterize tmpl with inverse ref
        tmpl.send(writer, ref)
        # submit the query
        logger.debug { "Submitting #{obj.qp} #{attribute} inverted query template #{tmpl.qp} ..." }
        persistence_service(tmpl).query(tmpl)
      end

      # Finds the object matching the specified object obj from the database and merges
      # the matching database values into obj. The find uses the obj secondary or
      # alternate key for the search.
      #
      # Returns nil if obj does not have a complete secondary or alternate key or if
      # there is no matching database object.
      #
      # If a match is found, then each missing obj non-domain-valued attribute is set to the
      # fetched attribute value and this method returns obj.
      #
      # Raises DatabaseError if more than object matches the obj attribute values or if
      # obj is a dependent entity that does not reference an owner.
      def find_object(obj)
       if @transients.include?(obj) then
          logger.debug { "Find #{obj.qp} obviated since the search was previously unsuccessful in the current database operation context." }
          return
        end
        @transients << obj

        logger.debug { "Fetching #{obj.qp} from the database..." }
        fetched = fetch_object(obj) || return
        # fetch_object can return obj; if so, then done
        return obj if obj.equal?(fetched)
        logger.debug { "Fetch #{obj.qp} matched database object #{fetched}." }
        @transients.delete(obj)
        
        # caCORE alert - there is no caCORE find utility method to update a search target with persistent content,
        # so it is done manually here.
        # recursively copy the nondomain attributes, esp. the identifer, of the fetched domain object references
        merge_fetched(obj, fetched)

        # caCORE alert - see query method alerts
        # inject the lazy loader for loadable domain reference attributes
        persistify(obj, fetched)
        obj
      end

      # Fetches the object matching the specified object obj from the database.
      #
      # @see #find_object
      def fetch_object(obj)
        # make the finder template with key attributes
        tmpl = finder_template(obj)
        # If a template could be made, then fetch on the template.
        # Otherwise, if there is an owner, then match on the fetched owner dependents.
        if tmpl then
          fetch_object_with_template(obj, tmpl)
        else
          fetch_object_by_fetching_owner(obj)
        end
      end
      
      # Fetches the object obj using the given template.
      def fetch_object_with_template(obj, template)
        # submit the query on the template
        logger.debug { "Query template for finding #{obj.qp}: #{template}." }
        result = query_on_template(template)

        # a fetch query which returns more than one result is an error.
        # possible cause is an incorrect secondary key.
        if result.size > 1 then
          # caCORE alert - annotations are not easily searchable; allow but bail out
          # TODO Annotation - always disable annotation find?
#          if CaRuby::Annotation === obj then
#            logger.debug { "Annotation #{obj} search unsuccessful with template #{template}." }
#            return
#          end
          msg = "More than one match for #{obj.class.qp} find with template #{template}."
          # it is an error to have an ambiguous result
          logger.error("Fetch error - #{msg}:\n#{obj.dump}")
          raise DatabaseError.new(msg)
        end

        result.first
      end

      # If obj is a dependent, then returns the obj owner dependent which matches obj.
      # Otherwise, returns nil.
      def fetch_object_by_fetching_owner(obj)
        owner = nil
        oattr = obj.class.owner_attributes.detect { |attr| owner = obj.send(attr) }
        return unless owner

        logger.debug { "Querying #{obj.qp} by matching on the fetched owner #{owner.qp} #{oattr} dependents..." }
        inverse = obj.class.attribute_metadata(oattr).inverse
        if inverse.nil? then
          raise DatabaseError.new("#{dep.class.qp} owner attribute #{oattr} does not have a #{obj.class.qp} inverse attribute")
        end
        # fetch the owner if necessary
        unless owner.identifier then
          find(owner) || return
          # if obj dependent was fetched with owner, then done
          return obj if obj.identifier
        end

        deps = query(owner, inverse)
        logger.debug { "Owner #{owner.qp} has #{deps.size} #{inverse} dependents: #{deps.qp}." }
        # If the dependent can be unambiguously matched to one of the results,
        # then return the matching result.
        obj.match_in_owner_scope(deps) unless deps.empty?
      end

      # Returns a copy of obj containing only those key attributes used in a find operation.
      #
      # caCORE alert - Bug #79: caCORE search fetches on all non-nil attributes, except
      # occasionally the identifier. There is no indication of how to identify uniquely
      # searchable attributes, so the secondary and alternate key is added manually in the
      # application configuration.
      def finder_template(obj)
        hash = finder_parameters(obj) || return
        @srch_tmpl_bldr.build_template(obj, hash)
      end

      # Fetches the given obj attribute from the database.
      # caCORE alert - there is no association fetch for caCORE 3.1 and earlier;
      # caCORE 4 association search is not yet adequately proven in caRuby testing.
      # Fall back on a general query instead (the devil we know). See also the
      # following alert.
      #
      # caCORE alert - caCORE search on a non-collection attribute returns a collection result,
      # even with the caCORE 4 association search. caRuby rectifies this by returning
      # an association fetch result consistent with the association attribute return type.
      #
      # caCORE alert - Preliminary indication is that caCORE 4 does not validate that
      # a non-collection association search returns at most one item.
      #
      # caCORE alert - Since the caCORE search result has toxic references which must be purged,
      # the detoxified copy loses reference integrity. E.g. a query on the children attribute of
      # a parent object forces lazy load of each child => parent reference separately resolving
      # in separate parent copies. There is no recognition that the children reference the parent
      # which generated the query. This anomaly is partially rectified in this fetch_association
      # method by setting the fetched objects inverse to the given search target object. The
      # inconsistent and inefficient caCORE behavior is further corrected by setting dependent
      # owners in the fetch result, as described in {#query_safe}.
      #
      # @param [Resource] obj the search target object
      # @param [Symbol] attribute the association to fetch
      # @raise [DatabaseError] if the search target object does not have an identifier
      def fetch_association(obj, attribute)
        logger.debug { "Fetching association #{attribute} for #{obj.qp}..." }
        # load the object if necessary
        unless exists?(obj) then
          raise DatabaseError.new("Can't fetch an association since the referencing object is not found in the database: #{obj}")
        end
        # fetch the reference
        result = query_safe(obj, attribute)
        # set inverse references
        inv_md = obj.class.attribute_metadata(attribute).inverse_attribute_metadata
        if inv_md and not inv_md.collection? then
          inv_obj = obj.copy
          result.each do |ref|
            logger.debug { "Setting fetched #{obj} #{attribute} inverse #{inv_md} to #{obj.qp} copy #{inv_obj.qp}..." }
            ref.send(inv_md.writer, inv_obj)
          end
        end
        # unbracket the result if the attribute is not a collection
        obj.class.attribute_metadata(attribute).collection? ? result : result.first
      end

      # Returns a copy of obj containing only those key attributes used in a find operation.
      #
      # caCORE alert - caCORE search fetches on all non-nil attributes, except occasionally the identifier
      # (cf. https://cabig-kc.nci.nih.gov/Bugzilla/show_bug.cgi?id=79).
      # there is no indication of how to identify uniquely searchable attributes, so the secondary key
      # is added manually in the application configuration.
      def finder_parameters(obj)
        key_value_hash(obj, obj.class.primary_key_attributes) or
        key_value_hash(obj, obj.class.secondary_key_attributes) or
        key_value_hash(obj, obj.class.alternate_key_attributes)
      end

      # Returns the attribute => value hash suitable for a finder template if obj has searchable values
      # for all of the given key attributes, nil otherwise.
      def key_value_hash(obj, attributes)
        # the key must be non-trivial
        return if attributes.nil_or_empty?
        # the attribute => value hash
        attributes.to_compact_hash do |attr|
          value = obj.send(attr)
          # validate that no key attribute is missing and each reference exists
          if value.nil_or_empty? then
            logger.debug { "Can't fetch #{obj.qp} based on #{attributes.qp} since #{attr} does not have a value." }
            return
          elsif obj.class.domain_attribute?(attr) then
            unless exists?(value) then
              logger.debug { "Can't fetch #{obj.qp} based on #{attributes.qp} since #{attr} does not exist in the database: #{value}." }
              return
            end
            # the finder value is a copy of the reference with just the identifier
            value.copy(:identifier)
          else
            value
          end
        end
      end

      # Returns whether the obj attribute value is either not a domain object reference or exists
      # in the database.
      #
      # Raises DatabaseError if the value is nil.
      def finder_attribute_value_exists?(obj, attr)
        value = obj.send(attr)
        return false if value.nil?
        obj.class.nondomain_attribute?(attr) or value.identifier
      end

      # Sets the template attribute to a new search reference object created from source.
      # The reference contains only the source identifier.
      # Returns the search reference, or nil if source does not exist in the database.
      def add_search_template_reference(template, source, attribute)
        return if not exists?(source)
        ref = source.copy(:identifier)
        template.set_attribute(attribute, ref)
        # caCORE alert - clear an owner inverse reference, since the template attr assignment might have added a reference
        # from ref to template, which introduces a template => ref => template cycle that causes a caCORE search infinite loop.
        inverse = template.class.attribute_metadata(attribute).derived_inverse
        ref.clear_attribute(inverse) if inverse
        logger.debug { "Search reference parameter #{attribute} for #{template.qp} set to #{ref} copied from #{source.qp}" }
        ref
      end

      # Takes a {Persistable#snapshot} of obj to track changes and adds a lazy loader.
      # If obj already has a snapshot, then this method is a no-op.
      # If the other fetched source object is given, then the obj snapshot is updated
      # with values from other which were not previously in obj.
      #
      # @param [Resource] obj the domain object to make persistable
      # @param [Resource] other the domain object with the snapshot content
      # @return [Resource] obj
      # @raise [ArgumentError] if obj is a collection and other is not nil
      def persistify(obj, other=nil)
        if obj.collection? then
          if other then raise ArgumentError.new("Database reader persistify other argument not supported") end
          obj.each { |ref| persistify(ref) }
          return obj
        end
        # merge or take a snapshot if necessary
        snapshot(obj, other) unless obj.snapshot_taken?
        # recurse to dependents before adding lazy loader to owner
        obj.dependents.each { |dep| persistify(dep) if dep.identifier }
        # add lazy loader to the unfetched attributes
        add_lazy_loader(obj)
        obj
      end

      # Adds this database's lazy loader to the given fetched domain object obj.
      def add_lazy_loader(obj)
        obj.add_lazy_loader(@lazy_loader, &@matcher)
      end

      # If obj has a snapshot and other is given, then merge any new fetched attribute values into the obj snapshot
      # which does not yet have a value for the fetched attribute.
      # Otherwise, take an obj snapshot.
      #
      # @param [Resource] obj the domain object to snapshot
      # @param [Resource] the source domain object
      # @return [Resource] the obj snapshot, updated with source content if necessary
      def snapshot(obj, other=nil)
        if obj.snapshot_taken? then
          if other then
            ovh = other.value_hash(other.class.fetched_attributes)
            obj.snapshot.merge(ovh) { |v, ov| v.nil? ? ov : v }
          end
        else
          obj.take_snapshot
        end
      end
    end
  end
end