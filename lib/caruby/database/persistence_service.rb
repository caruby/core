require 'caruby/util/version'
require 'caruby/database'
require 'caruby/util/stopwatch'

import 'gov.nih.nci.common.util.HQLCriteria'

module CaRuby
  # A PersistenceService wraps a caCORE application service.
  class PersistenceService
    # The service name.
    attr_reader :name

    # The {Util::Stopwatch} which captures the time spent in database operations performed by the application service.
    attr_reader :timer

    # Creates a new PersistenceService with the specified application service name.
    def initialize(name, opts={})
      @name = name
      ver_opt = opts[:version]
      @version = ver_opt.to_s.to_version if ver_opt
      @host = opts[:host] || "localhost"
      @timer = Stopwatch.new
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
    # caCORE alert - this method returns the direct result of calling the +caCORE+ application service
    # search method. Calling reference attributes of this result is broken by +caCORE+ design.
    def query(template_or_hql, *path)
      String === template_or_hql ? query_hql(template_or_hql) : query_template(template_or_hql, path)
    end

    # Submits the create to the application service and returns the created object.
    #
    # caCORE alert - this method returns the direct result of calling the +caCORE+ application service
    # create method. Calling reference attributes of this result is broken by +caCORE+ design.
    def create(obj)
      logger.debug { "Submitting create #{obj.pp_s(:single_line)} to application service #{name}..." }
      begin
        dispatch { |svc| svc.create_object(obj) }
      rescue Exception => e
        logger.error("Error creating #{obj} - #{e.message}\n#{dump(obj)}")
        raise
      end
    end

    # Submits the update to the application service and returns obj.
   def update(obj)
      logger.debug { "Submitting update #{obj.pp_s(:single_line)} to application service #{name}..." }
      begin
        dispatch { |svc| svc.update_object(obj) }
      rescue Exception => e
        logger.error("Error updating #{obj} -  #{e.message}\n#{dump(obj)}")
        raise
      end
   end

    # Submits the delete to the application service.
    def delete(obj)
      logger.debug { 'Deleting #{obj}.' }
      begin
        dispatch { |svc| svc.remove_object(obj) }
      rescue Exception => e
        logger.error("Error deleting #{obj}  - #{e.message}\n#{dump(obj)}")
        raise
      end
    end

    # Returns the CaCORE ApplicationServiceProvider wrapped by this PersistenceService.
    def app_service
      url = "http://#{@host}:8080/#{name}/http/remoteService"
      logger.debug { "Connecting to service provider at #{url}..." }
      ApplicationServiceProvider.remote_instance(url)
    end

    private

    # The first caCORE Version which supports association search.
    ASSOCIATION_SUPPORT_VERSION = "4".to_version

    # Calls the block given to this method. The execution duration is captured in the {#timer}.
    # Returns the block result.
    def dispatch
      result = nil
      seconds = @timer.run { result = yield app_service }.elapsed
      millis = (seconds * 1000).round
      logger.debug { "Database operation took #{millis} milliseconds." }
      result
    end

    def query_hql(hql)
      logger.debug { "Building HQLCriteria..." }
      criteria = HQLCriteria.new(hql)
      # caCORE alert - query target parameter is necessary for caCORE 3.x but deprecated in caCORE 4+
      # TODO caCORE 4 - remove target parameter
      target = hql[/from\s+(\S+)/i, 1]
      raise DatabaseError.new("HQL does not contain a FROM clause: #{hql}") unless target
      logger.debug { "Calling application service query on target class #{target} with following HQL:\n#{hql}" }
      begin
        dispatch { |svc| svc.query(criteria, target) }
      rescue Exception => e
        logger.error("Error querying on HQL - #{$!}:\n#{hql}")
        raise
      end
    end

    def query_template(template, path)
      if path.length == 1 and template.identifier and @version and @version >= ASSOCIATION_SUPPORT_VERSION then
        return query_association_post_caCORE_v4(template, path.first)
      end
      logger.debug { "Searching using template #{template.qp}#{', path ' + path.join('.') unless path.empty?}..." }
      # collect the class search path from the reference attribute domain type Java class names
      class_name_path = []
      path.inject(template.class) do |type, attr|
        ref_type = type.domain_type(attr)
        raise DatabaseError.new("Attribute in search attribute path #{path.join('.')} is not a #{type} domain reference attribute: #{attr}") if ref_type.nil?
        class_name_path << ref_type.java_class.name
        ref_type
      end
      # the caCORE app service search path is in reverse path traversal order (go figure!)
      reverse_class_name_path = class_name_path.reverse << template.java_class
      # call the caCORE app service search
      logger.debug { "Calling application service search with template #{template.qp}, target-first class path #{reverse_class_name_path.pp_s(:single_line)}, criterion:\n#{dump(template)}" }
      begin
        dispatch { |svc| svc.search(reverse_class_name_path.join(','), template) }
      rescue Exception => e
        logger.error("Error searching on template #{template}#{', path ' + path.join('.') unless path.empty?} - #{$!}\n#{dump(template)}")
        raise
      end
    end

    # Returns an array of domain objects associated with obj through the specified attribute.
    # This method uses the +caCORE+ v. 4+ getAssociation application service method.
    #
    # *Note*: this method is only available for caBIG application services which implement +getAssociation+.
    # Currently, this includes +caCORE+ v. 4.0 and above.
    # This method raises a DatabaseError if the application service does not implement +getAssociation+.
    #
    # Raises DatabaseError if the attribute is not an a domain attribute or the associated objects were not fetched.
    def query_association_post_caCORE_v4(obj, attribute)
     assn = obj.class.association(attribute)
     begin
        result = dispatch { |svc| svc.association(obj, assn) }
      rescue Exception => e
        logger.error("Error fetching association #{obj} - #{e.message}\n#{dump(obj)}")
        raise
      end
    end

    def dump(obj)
      Resource === obj ? obj.dump : obj.to_s
    end
  end
end