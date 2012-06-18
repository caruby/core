require 'generator'
require 'jinx/helpers/collection'
require 'jinx/helpers/validation'
require 'jinx/helpers/options'
require 'jinx/helpers/visitor'
require 'jinx/helpers/inflector'
require 'caruby/database/persistable'
require 'caruby/database/persistence_service'
require 'caruby/database/operation'
require 'caruby/database/reader'
require 'caruby/database/writer'
require 'caruby/database/persistifier'
require 'caruby/database/sql_executor'

module CaRuby
  # Database operation error.
  class DatabaseError < RuntimeError; end

  # A Database mediates access to a caBIG database. Database is a facade for caBIG application service
  # database operations. Database supports the query, create, update and delete operations supported by
  # the application service.
  #
  # Database strives to provide a simple WYEIWYG (What You Expect Is What You Get) API, consisting of
  # the following workhorse methods:
  # * {Reader#query} - fetch domain objects which match a template
  # * {Reader#find} - fetch a specific domain object by key
  # * {Writer#save} - if a domain object exists in the database, then update it, otherwise create it
  #
  # Any domain object can serve as a query argument. If an optional attribute path is specified, then
  # that path is followed to the result, e.g.:
  #   database.query(study, :coordinator)
  # returns the coordinators of studies which match the +study+ template.
  #
  # A domain object find argument must contain enough data to determine whether it exists in the database,
  # i.e. the find argument has a database identifier or a complete secondary key.
  #
  # The {Writer#save} method creates or updates references as necessary to persist its argument domain object.
  # It is not necessary to fetch references first or follow dependency ordering rules, which can be
  # implicit and tortuous in caBIG applications. Build the object you want to persist and call the
  # store method. {Jinx::Resource} sets reasonable default values, recognizes application dependencies and
  # steers around caBIG idiosyncracies to the extent possible.
  class Database
    include Reader, Writer, Persistifier

    # The application and database connection options.
    ACCESS_OPTS = [
      [:user, '-u USER', '--user USER', 'the application login user'],
      [:password, '-p PSWD', '--password PSWD', 'the application login password'],
      [:host, '--host HOST', 'the application host name'],
      [:port, '--port PORT', 'the application port number'],
      [:classpath, '--classpath PATH', 'the application client classpath']
    ]
    
    attr_reader :operations
    
    # @return [PersistenceService] the services used by this database
    attr_reader :persistence_services

    # Creates a new Database with the specified service name and options.
    #
    # @quirk caCORE obtaining a caCORE session instance mysteriously depends on referencing the
    #   application service first. Therefore, the default persistence service appService method must
    #   be called after it is instantiated and before the session is instantiated. However, when
    #   the appService method is called just before a session is acquired, then this call corrupts
    #   the object state of existing objects.
    #
    #   Specifically, when a CaTissue::CollectionProtocol is created which references a
    #   CaTissue::CollectionProtocolRegistration which in turn references a CaTissue::Participant,
    #   then the call to PersistenceService.appService replaces the CaTissue::Participant
    #   reference with a difference CaTissue::Participant instance. The work-around for
    #   this extremely bizarre bug is to call appService immediately after instantiating
    #   the default persistence service.
    #
    #   This bug might be a low-level JRuby-Java-caCORE-Hibernate confusion where something in
    #   caCORE stomps on an existing JRuby object graph. To reproduce, move the appService call
    #   to the start_session method and run the +PSBIN::MigrationTest+ biopsy save test case.
    #
    # @param [String] service_name the name of the default {PersistenceService}
    # @param [{Symbol => String}, nil] opts the access options, or nil if specified as a block
    # @option opts [String] :host application service host name
    # @option opts [String] :login application service login user
    # @option opts [String] :password application service login password
    # @yield the access options defined by a block rather than a parameter
    # @example
    #   Database.new(:user => 'perdita', :password => 'changeMe')
    def initialize(service_name, opts=nil)
      super()
      # The options can be defined in a block.
      opts ||= yield if block_given?
      if opts.nil? then raise ArgumentError.new("Missing required database access properties") end
      @user = Options.get(:user, opts)
      @password = Options.get(:password, opts)
      host = Options.get(:host, opts)
      port = Options.get(:port, opts)
      # The class => service hash is populated with the default service.
      @def_persist_svc = PersistenceService.new(service_name, :host => host, :port => port)
      @persistence_services = [@def_persist_svc].to_set
      @cls_svc_hash = Hash.new(@def_persist_svc)
      # the create/update nested operations
      @operations = []
      # the objects for which exists? is unsuccessful in the context of a nested operation
      @transients = Set.new
    end
    
    # @return [Boolean] whether there is an active session
    def open?
      !!@session
    end
    
    # @return [Boolean] whether this database is not {#open?}
    def closed?
      not open?
    end

    # Calls the block given to this method with this database as an argument, and closes the
    # database when done.
    #
    # @param [String, nil] user the application login user
    # @param [String, nil] password the application login password
    # @yield [database] the operation to perform on the database
    # @yieldparam [Database] database self
    def open(user=nil, password=nil)
      raise ArgumentError.new("Database open requires an execution block") unless block_given?
      raise DatabaseError.new("The caRuby application database is already in use.") if open?
      # reset the execution timers
      persistence_services.each { |svc| svc.timer.reset }
      # Start the session.
      start_session(user, password)
      # Call the block and close when done.
      yield(self) ensure close
    end
    
    # @return [Numeric] the execution time in seconds spent since the last open
    def execution_time
      persistence_services.inject(0) do |total, svc|
        st = svc.timer.elapsed
        total + st
      end
    end

    # Returns the PersistanceService to use for the given {Jinx::Resource} class.
    # This base method always returns the standard application service.
    # Subclasses can override for specialized services. A session is started
    # on demand if necessary.
    #
    # @param [Class] klass the domain object class
    # @return [PersistanceService] the corresponding service
    def persistence_service(klass)
       unless Class === klass then
         raise ArgumentError.new("#{self} persistence_service argument is not a Class: {#klass.qp}")
       end
       @def_persist_svc
    end
    
    # Adds the given service to this database.
    #
    # @param [PersistenceService] service the service to add
    def add_persistence_service(service)
      @persistence_services << service
    end
    
    # Imports the caCORE +ClientSession+ class on demand.
    def self.const_missing(sym)
      if sym == :ClientSession then
        java_import Java::gov.nih.nci.system.comm.client.ClientSession
      else
        super
      end
    end

    alias :to_s :print_class_and_id

    alias :inspect :to_s

    ## Utility classes and methods, used by Query and Store mix-ins ##

    private

    # Releases database resources. This method should be called when database interaction
    # is completed.
    def close
      return if @session.nil?
      begin
        @session.terminate_session
      rescue Exception => e
        logger.error("Session termination unsuccessful - #{e.message}")
      end
      # clear the cache
      clear
      logger.info("Disconnected from application server.")
      @session = nil
    end
    
    # A mergeable autogenerated operation is recursively defined as:
    # * a create of an object with auto-generated dependents
    # * an update of an auto-generated dependent in the context of a mergeable autogenerated operation
    #
    # @return [Boolean] whether the innermost operation conforms to the above criterion
    def mergeable_autogenerated_operation?
      # the inner operation subject
      inner = nil
      @operations.reverse_each do |op|
        if inner and op.subject != inner.owner then
          # not a dependent
          return false
        end
        if op.type == :create then
          # innermost or owner create
          return (not op.subject.class.autogenerated_dependent_attributes.empty?)
        elsif op.type != :update then
          # not a save
          return false
        end
        # iterate to the scoping operation
        inner = op.subject
      end
      false
    end
    
    # Performs the operation given by the given op symbol on obj by calling the block given to this method.
    # Lazy loading is suspended during the operation.
    #
    # @param [:find, :query, :create, :update, :delete] op the database operation type
    # @param [Resource] obj the domain object on which the operation is performed
    # @param opts (#see Operation#initialize)
    # @yield the database operation block
    # @return the result of calling the operation block
    def perform(op, obj, opts=nil, &block)
      op_s = op.to_s.capitalize_first
      pa = Options.get(:attribute, opts)
      attr_s = " #{pa}" if pa
      ag_s = " autogenerated" if Options.get(:autogenerated, opts)
      ctxt_s = " in context #{print_operations}" unless @operations.empty?
      logger.info(">> #{op_s}#{ag_s} #{obj.pp_s(:single_line)}#{attr_s}#{ctxt_s}...")
      # Clear the error flag.
      @error = nil
      # Push the operation on the nested operation stack.
      @operations.push(Operation.new(op, obj, opts))
      begin
        # perform the operation
        result = perform_operation(&block)
      rescue Exception => e
        # If the current operation is the immediate cause, then print the
        # error to the log.
        if @error.nil? then
          msg = "Error performing #{op} on #{obj}:\n#{e.message}\n#{obj.dump}\n#{e.backtrace.qp}"
          logger.error(msg)
          @error = e
        end
        raise e
      ensure
        # the operation is done
        @operations.pop
        # If this is a top-level operation, then clear the transient set.
        if @operations.empty? then @transients.clear end
      end
      logger.info("<< Completed #{obj.qp}#{attr_s} #{op}.")
      result
    end
    
    # Calls the given block with the lazy loader suspended.
    # The database is opened, if necessary.
    #  
    # @yield the database operation block
    # @return the result of calling the operation block 
    def perform_operation(&block)
      if closed? then
       open { perform_operation(&block) }
      else  
        @lazy_loader.suspend { yield }
      end
    end
    
    def each_persistence_service(&block)
      ObjectSpace.each_object(PersistenceService, &block)
    end
    
    # Initializes the default application service.
    def start_session(user=nil, password=nil)
      user ||= @user
      password ||= @password
      if user.nil? then raise DatabaseError.new('The caRuby application is missing the login user') end
      if password.nil? then raise DatabaseError.new('The caRuby application is missing the login password') end
      @session = ClientSession.instance
      connect(user, password)
    end

    # Returns the current database operation stack as a String.
    def print_operations
      ops = @operations.reverse.map do |op|
        attr_s = " #{op.attribute}" if op.attribute
        "#{op.type.to_s.capitalize_first} #{op.subject.qp}#{attr_s}"
      end
      ops.qp
    end

    # Connects to the database.
    def connect(user, password)
      logger.debug { "Connecting to application server with login id #{user}..." }
      begin
        @session.start_session(user, password)
      rescue Exception => e
        logger.error("Login of #{user} with password #{password} was unsuccessful - #{e.message}")
        raise e
      end
      logger.info("Connected to application server.")
    end
  end
end