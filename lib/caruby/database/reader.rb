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
        # the query template builder
        @srch_tmpl_bldr = SearchTemplateBuilder.new
        # the fetch result matcher
        @matcher = FetchedMatcher.new
        # the fetched copier
        copier = Proc.new do |src|
          copy = src.copy
          logger.debug { "Fetched #{src.qp} copied to #{copy.qp}." }
          copy
        end
        # visitor that merges the fetched object graph
        @ftchd_mrg_vstr = MergeVisitor.new(:matcher => @matcher, :copier => copier) { |ref| ref.class.fetched_domain_attributes }
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

      # Returns whether the given domain object has a database identifier or exists in the database.
      # This method fetches the object from the database if necessary.
      #
      # @param [Resource, <Resource>] obj the domain object(s) to find
      # @return [Boolean] whether the domain object(s) exist in the database
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

      RESULT_PRINTER = PrintWrapper.new { |obj| obj.pp_s }

      # Queries the given obj_or_hql as described in {#query} and makes a detoxified copy of the
      # toxic caCORE search result.
      #
      # caCORE alert - The query result consists of new domain objects whose content is copied
      # from the caBIG application search result. The caBIG result is Hibernate-enhanced but
      # sessionless. This result contains toxic broken objects whose access methods fail.
      # Therefore, this method sanitizes the toxic caBIG result to reflect the persistent state
      # of the domain objects.
      #
      # @param (see #query)
      # @return (see #query)
      def query_safe(obj_or_hql, *path)
        # the caCORE search result
        toxic = query_toxic(obj_or_hql, *path)
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
        perform(:query, obj_or_hql, :attribute => path_s) { query_with_path(obj_or_hql, path) }
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
          # if there is an attribute, then compose an hql query with a recursive object query
          if attribute then
            query_safe(hql).map { |ref| query_with_attribute(ref, attribute) }.flatten
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
      
      # Merges fetched into target. The fetched references are recursively merged.
      #
      # @param [Resource] source the fetched domain object result
      # @param [Resource] target the domain object find argument
      def merge_fetched(source, target)
        @ftchd_mrg_vstr.visit(source, target) { |src, tgt| tgt.copy_volatile_attributes(src) }
      end

      def print_query_result(result)
        count_s = 'result object'.quantify(result.size)
        result_printer = result.wrap { |item| RESULT_PRINTER.wrap(item) }
        "Persistence service query returned #{count_s}: #{result_printer.pp_s(:single_line)}"
      end

      def query_hql(hql)
        java_name = hql[/from\s+(\S+)/i, 1]
        raise DatabaseError.new("Could not determine target type from HQL: #{hql}") if java_name.nil?
        tgt = Class.to_ruby(java_name)
        persistence_service(tgt).query(hql)
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
        if obj.identifier then
          query_on_identifier(obj, attribute)
        elsif invertible_query?(obj, attribute) then
          query_with_inverted_reference(obj, attribute)
        else
          tmpl = @srch_tmpl_bldr.build_template(obj)
          return Array::EMPTY_ARRAY if tmpl.nil?
          query_on_template(tmpl, attribute)
        end
      end

      # Returns an array of objects fetched from the database which matches
      # the given template and follows the given optional domain attribute.
      def query_on_template(template, attribute=nil)
        tgt = attribute ? template.class.domain_type(attribute) : template.class
        svc = persistence_service(tgt)
        attribute ? svc.query(template, attribute) : svc.query(template)
      end

      # Queries on the given template and attribute by issuing a HQL query with an identifier condition.
      #
      # @param (see #query_object)
      def query_on_identifier(obj, attribute=nil)
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
        logger.debug { "Querying on #{obj} #{attribute} using HQL identifier criterion..." }

        query_hql(hql)
      end

      # Returns whether the query specified by the given search object and attribute can be
      # inverted as a query on a template of type attribute which references the object.
      # This condition holds if the search object has a key and attribute is a non-abstract
      # reference with a searchable inverse.
      #
      # @param (see #query_object)
      # @return [Boolean] whether the query can be inverted
      def invertible_query?(obj, attribute=nil)
        return false if attribute.nil?
        attr_md = obj.class.attribute_metadata(attribute)
        return false if attr_md.type.abstract?
        inv_md = attr_md.inverse_metadata
        inv_md and inv_md.searchable? and finder_parameters(obj)
      end

      # Queries the given query object attribute by querying an attribute type template which references obj.
      #
      # caCORE alert - caCORE caCORE search enters an infinite loop when the search argument has an object
      # reference graph cycle. Work-around is to ensure that reference integrity is broken in the search
      # argument by not setting inverse attributes.
      #
      # @param (see #query_object)
      def query_with_inverted_reference(obj, attribute=nil)
        attr_md = obj.class.attribute_metadata(attribute)
        logger.debug { "Querying on #{obj.qp} #{attribute} by inverting the query as a #{attr_md.type.qp} #{attr_md.inverse} reference query..." }
        # the search reference template
        ref = finder_template(obj)
        # the attribute inverse query template
        tmpl = attr_md.type.new
        # the inverse attribute
        inv_md = tmpl.class.attribute_metadata(attr_md.inverse)
        # The Java property writer to set the tmpl inverse to ref.
        # Use the property writer rather than the attribute writer in order to curtail automatically
        # adding tmpl to the ref attribute value when the inv_md attribute is set to ref.
        wtr = inv_md.property_writer
        # parameterize tmpl with inverse ref
        tmpl.send(wtr, ref)
        # submit the query
        logger.debug { "Submitting #{obj.qp} #{attribute} inverted query template #{tmpl.qp} ..." }
        persistence_service(tmpl.class).query(tmpl)
      end

      # Finds the database content matching the given search object and merges the matching
      # database values into the object. The find uses the search object secondary or alternate
      # key for the search.
      #
      # Returns nil if the search object does not have a complete secondary or alternate key or if
      # there is no matching database record.
      #
      # If a match is found, then each missing search object non-domain-valued attribute is set to
      # the fetched attribute value and this method returns the search object.
      #
      # @param obj (see #find)
      # @return [Resource, nil] obj if there is a matching database record, nil otherwise
      # @raise [DatabaseError] if more than object matches the obj attribute values or if
      #   the search object is a dependent entity that does not reference an owner
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
        merge_fetched(fetched, obj)
        # caCORE alert - see query method alerts.
        # Inject the lazy loader for loadable domain reference attributes.
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
          msg = "More than one match for #{obj.class.qp} find with template #{template}."
          # it is an error to have an ambiguous result
          logger.error("Fetch error - #{msg}:\n#{obj}")
          raise DatabaseError.new(msg)
        end

        result.first
      end

      # If obj is a dependent, then returns the obj owner dependent which matches obj.
      # Otherwise, returns nil.
      #
      # @param [Resource] the domain object to fetch
      # @return [Resource, nil] the domain object if it matches a dependent, nil otherwise 
      def fetch_object_by_fetching_owner(obj)
        owner = nil
        oattr = obj.class.owner_attributes.detect { |attr| owner = obj.send(attr) }
        return unless owner

        logger.debug { "Querying #{obj.qp} by matching on the owner #{owner.qp} #{oattr} dependents..." }
        inv_md = obj.class.attribute_metadata(oattr)
        if inv_md.nil? then
          raise DatabaseError.new("#{dep.class.qp} owner attribute #{oattr} does not have a #{owner.class.qp} inverse dependent attribute.")
        end
        inverse = inv_md.inverse
        # fetch the owner if necessary
        unless owner.identifier then
          find(owner) || return
          # if obj dependent was fetched with owner, then done
          if obj.identifier then
            logger.debug { "Found #{obj.qp} by fetching the owner #{owner}." }
            return obj
          end
        end

        # try to match a fetched owner dependent
        deps = lazy_loader.enable { owner.send(inverse) }
        if obj.identifier then
          logger.debug { "Found #{obj.qp} by fetching the owner #{owner} #{inverse} dependent #{deps.qp}." }
          return obj
        else
          logger.debug { "#{obj.qp} does not match a fetched owner #{owner} #{inverse} dependent #{deps.qp}." }
          nil
        end
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
      # inconsistent and inefficient caCORE behavior is further corrected by setting inverse
      # owners when the fetch result is persistified, as described in {Persistifier#persistify}.
      # Callers who do not persistify the result should call {Persistifier#set_inverses} on the
      # result.
      #
      # @param [Resource] obj the search target object
      # @param [Symbol] attribute the association to fetch
      # @raise [DatabaseError] if the search target object does not have an identifier
      def fetch_association(obj, attribute)
        logger.debug { "Fetching association #{attribute} for #{obj}..." }
        # load the object if necessary
        unless exists?(obj) then
          raise DatabaseError.new("Can't fetch an association since the referencing object is not found in the database: #{obj}")
        end
        # fetch the reference
        result = query_safe(obj, attribute)
        # set the result inverse references
        inv_md = obj.class.attribute_metadata(attribute).inverse_metadata
        if inv_md and not inv_md.collection? then
          inv_obj = obj.copy(:identifier)
          result.each do |ref|
            logger.debug { "Setting fetched #{obj} #{attribute} value #{ref} inverse #{inv_md} to #{obj} copy #{inv_obj.qp}..." }
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
    end
  end
end