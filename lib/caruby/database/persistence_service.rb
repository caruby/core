require 'jinx/helpers/options'
require 'jinx/helpers/stopwatch'

module CaRuby
  # A PersistenceService is a database mediator which implements the {#query} {#create}, {#update}
  # and {#delete} methods.
  class PersistenceService
    # The {Stopwatch} which captures the time spent in database operations performed by the
    # application service.
    attr_reader :timer

    # Creates a new PersistenceService with the specified application service provider and options.
    # If the service argument is given, that that service is used. Otherwise, the given provider
    # block is called to obtain a service before each service call.
    #
    # @param service the caBIG application service
    # @param [Symbol, {Symbol => Boolean}, nil] opts the service options
    # @option opts [Boolean] :association_query_support whether the application service implements
    #   +getAssociation+ (default is +false+)
    # @yield obtains the application service
    def initialize(service=nil, opts=nil, &provider)
      @app_svc, @provider = service, provider
      @association_query_support = Options.get(:association_query_support, opts, false)
      @timer = Jinx::Stopwatch.new
    end

    ## Database access methods ##

    # Returns an array of objects fetched from the database which match the given template_or_hql.
    #
    # If template_or_hql is a String, then the HQL is submitted to the service.
    #
    # Otherwise, the template_or_hql is a query template domain
    # object following the given attribute path. The query condition is determined by the values set in the
    # template. Every non-nil attribute in the template is used as a select condition.
    #
    # @quirk caCORE this method returns the direct result of calling the +caCORE+ application service
    #   search method. Calling reference attributes of this result is broken by +caCORE+ design.
    def query(template_or_hql, *path)
      result = String === template_or_hql ? query_hql(template_or_hql) : query_template(template_or_hql, path)
    end

    # Submits the create to the application service and returns the created object.
    #
    # @quirk caCORE this method returns the direct result of calling the +caCORE+ application service
    #   create method. Calling reference attributes of this result is broken by +caCORE+ design.
    def create(obj)
      logger.debug { "Submitting create #{obj.pp_s(:single_line)} to the application service..." }
      dispatch { |svc| create_with_service(obj, svc) }
    end

    # Submits the update to the application service and returns obj.
   def update(obj)
      logger.debug { "Submitting update #{obj.pp_s(:single_line)} to the application service..." }
      dispatch { |svc| update_with_service(obj, svc) }
   end

    # Submits the delete to the application service.
    def delete(obj)
      logger.debug { 'Deleting #{obj}.' }
      dispatch { |svc| svc.remove_object(obj) }
    end

    # Returns the {ApplicationService} remote instance.
    #
    # @return the CaCORE application service wrapped by this PersistenceService
    def app_service
      @app_svc || @provider.call
    end

    private
    
    # Calls the block given to this method. The execution duration is captured in the {#timer}.
    #
    # @return the block result
    def time
      result = nil
      seconds = @timer.run { result = yield }.elapsed
      millis = (seconds * 1000).round
      logger.debug { "Database operation took #{millis} milliseconds." }
      result
    end

    # Calls the block given to this method on the #{app_service}.
    # The execution duration is captured in the {#timer}.
    #
    # @return the block result
    def dispatch
      time { yield app_service }
    end
    
    # @quirk caCORE 4.x The caCORE 4.x API replaces +createObject+ with the misnamed +executeQuery+
    #   taking a +gov.nih.nci.system.query.example.InsertExampleQuery+ argument. caRuby supports both
    #   caCORE versions in this method with backward compatibility by calling the correct caCORE
    #   method. 
    def create_with_service(obj, svc)
      if svc.respond_to?(:create_object) then
        svc.create_object(obj)
      else
        query = Java::gov.nih.nci.system.query.example.InsertExampleQuery.new(obj)
        svc.executeQuery(query).getObjectResult
      end
    end
    
    # @quirk caCORE 4.x The caCORE 4.x API replaces +updateObject+ with the misnamed +executeQuery+
    #   taking a +gov.nih.nci.system.query.example.UpdateExampleQuery+ argument. caRuby supports both
    #   caCORE versions in this method with backward compatibility by calling the correct caCORE
    #   method. 
    def update_with_service(obj, svc)
      if svc.respond_to?(:update_object) then
        svc.update_object(obj)
      else
        query = Java::gov.nih.nci.system.query.example.UpdateExampleQuery.new(obj)
        svc.executeQuery(query).getObjectResult
      end
    end
    
    # Dispatches the given HQL to the application service.
    #
    # @quirk caCORE query target parameter is necessary for caCORE 3.x but deprecated in caCORE 4+.
    #
    # @param [String] hql the HQL to submit
    def query_hql(hql)
      logger.debug { "Building HQLCriteria..." }
      criteria = hql_class.new(hql)
      target = hql[/from\s+(\S+)/i, 1]
      raise DatabaseError.new("HQL does not contain a FROM clause: #{hql}") unless target
      logger.debug { "Submitting search on target class #{target} with the following HQL:\n  #{hql}" }
      begin
        dispatch { |svc| svc.query(criteria, target) }
      rescue Exception => e
        logger.error("Error querying on HQL - #{$!}:\n#{hql}")
        raise e
      end
    end
    
    # @quirk caTissue 2.0 The HQLCriteria package changed from +gov.nih.nci.common.util.+ to
    #   +gov.nih.nci.system.query.hibernate+.
    def hql_class
      @hql_cls ||= Java::gov.nih.nci.system.query.hibernate.HQLCriteria rescue Java::gov.nih.nci.common.util.HQLCriteria
    end

    # Returns an array of domain objects associated with the given template through the
    # specified attribute path.
    #
    # @return [<Resource>] the fetched domain objects
    # @raise [Exception] if the fetch results in an application error
    def query_template(template, path)
      if path.empty? then
        query_simple(template)
      elsif path.length == 1 and template.identifier and @association_query_support then
        query_association(template, path.first)
      else
        query_search_path(template, path)
      end
    end

    # Returns the +caCORE+ +getAssociation+ result.
    #
    # *Note*: this method is only available for caBIG application services which implement +getAssociation+.
    # Currently, this includes +caCORE+ v. 4.0 and above.
    def query_association(obj, attribute)
     assn = obj.class.association(attribute)
     begin
        result = dispatch { |svc| svc.association(obj, assn) }
      rescue Exception
        logger.error("Error fetching association #{obj} - #{$!}")
        raise
      end
    end
    
    def query_simple(template)
      # Call the caCORE app service search.
      logger.debug { "Submitting search with template #{template.qp}, criterion:\n#{dump(template)}" }
      begin
        dispatch { |svc| svc.search(template.java_class, template) }
      rescue Exception
        logger.error("Error searching on template #{template} - #{$!}\n#{dump(template)}")
        raise
      end
    end

    # Returns the +caCORE+ +search+ result.
    def query_search_path(template, path)
      logger.debug { "Searching using template #{template.qp}#{', path ' + path.join('.') unless path.empty?}..." }
      # Collect the class search path from the reference attribute domain type Java class names.
      class_name_path = []
      path.inject(template.class) do |type, pa|
        ref_type = type.domain_type(pa)
        raise DatabaseError.new("Property in search attribute path #{path.join('.')} is not a #{type} domain reference attribute: #{pa}") if ref_type.nil?
        class_name_path << ref_type.java_class.name
        ref_type
      end
      # The caCORE app service search path is in reverse path traversal order (go figure!).
      spath = class_name_path.reverse << template.java_class
      # Call the caCORE app service search.
      logger.debug { "Submitting search with template #{template.qp}, target-first class path #{spath.pp_s(:single_line)}, criterion:\n#{dump(template)}" }
      begin
        dispatch { |svc| svc.search(spath.join(','), template) }
      rescue Exception
        logger.error("Error searching on template #{template}#{', path ' + path.join('.') unless path.empty?} - #{$!}\n#{dump(template)}")
        raise
      end
    end

    def dump(obj)
      Jinx::Resource === obj ? obj.dump : obj.to_s
    end
  end
end