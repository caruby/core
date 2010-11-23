require 'generator'
require 'caruby/util/log'
require 'caruby/util/collection'
require 'caruby/util/validation'
require 'caruby/util/options'
require 'caruby/util/visitor'
require 'caruby/util/inflector'
require 'caruby/database/persistable'
require 'caruby/database/reader'
require 'caruby/database/writer'
require 'caruby/database/persistence_service'

# the caBIG client classes
import 'gov.nih.nci.system.applicationservice.ApplicationServiceProvider'
import 'gov.nih.nci.system.comm.client.ClientSession'

module CaRuby
  # Database operation error.
  class DatabaseError < RuntimeError; end

  # A Database mediates access to a caBIG database. Database is a facade for caBIG application service
  # database operations. Database supports the query, create, update and delete operations supported by
  # the application service.
  #
  # Database strives to provide a simple WYEIWYG (What You Expect Is What You Get) API, consisting of
  # the following workhorse methods:
  # * {Query#query} - fetch domain objects which match a template
  # * {Store#find} - fetch a specific domain object by key
  # * {Store#store} - if a domain object exists in the database, then update it, otherwise create it
  #
  # Any domain object can serve as a query argument. If an optional attribute path is specified, then
  # that path is followed to the result, e.g.:
  #   database.query(study, :coordinator)
  # returns the coordinators of studies which match the +study+ template.
  #
  # A domain object find argument must contain enough data to determine whether it exists in the database,
  # i.e. the find argument has a database identifier or a complete secondary key.
  #
  # The {Store#store} method creates or updates references as necessary to persist its argument domain object.
  # It is not necessary to fetch references first or follow dependency ordering rules, which can be
  # implicit and tortuous in caBIG applications. Build the object you want to persist and call the
  # store method. CaRuby::Resource sets reasonable default values, recognizes application dependencies and steers
  # around caBIG idiosyncracies to the extent possible.
  class Database
    include Reader, Writer, Validation
    
    attr_reader :operations

    # Creates a new Database with the specified service name and options.
    #
    # @param [String] service_name the name of the default {PersistenceService}
    # @param [{Symbol => String}] opts access options
    # @option opts [String] :login application service login user
    # @option opts [String] :password application service login password
    # @example
    #   Database.new(:user => 'perdita', :password => 'changeMe')
    def initialize(service_name, opts)
      super()
      # the fetched object cache
      @cache = create_cache
      @defaults = {}
      @user = Options.get(:user, opts)
      @password = Options.get(:password, opts)
      @host = Options.get(:host, opts)
      # class => service hash; default is the catissuecore app service
      @def_persist_svc = PersistenceService.new(service_name, :host => @host)
      @cls_svc_hash = Hash.new(@def_persist_svc)
      # the create/update nested operations
      @operations = []
      # the objects for which exists? is unsuccessful in the context of a nested operation
      @transients = Set.new
    end

    # Calls the block given to this method with this database as an argument, and closes the
    # database when done.
    #
    # @yield [database] the operation to perform on the database
    # @yieldparam [Database] database self
    def open
      # reset the execution timers
      persistence_services.each { |svc| svc.timer.reset }
      # call the block and close when done
      yield(self) ensure close
    end

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
      @cache.clear
      logger.info("Disconnected from application server.")
      @session = nil
    end
    
   # Returns the execution time spent since the last open.
   def execution_time
      persistence_services.inject(0) do |total, svc|
        st = svc.timer.elapsed
        total + st
      end
    end

    # Returns the PersistanceService to use for the given domain object obj,
    # or the default service if obj is nil.
    def persistence_service(obj=nil)
      start_session if @session.nil?
      return @def_persist_svc if obj.nil?
      klass = Class === obj ? obj : obj.class
      @cls_svc_hash[klass]
    end

    # Returns all PersistanceServices used by this database.
    def persistence_services
      [@def_persist_svc].to_set.merge!(@cls_svc_hash.values)
    end
    
    # Returns the database operation elapsed real time since the last open.
    def database_time
      persistence_services.inject(0) do |total, svc|
        st = svc.timer.elapsed
        # reset the timer for the next test case
        svc.timer.reset
        total + st
      end
    end
    
    # A mergeable autogenerated operation is recursively defined as:
    # * a create
    # * an update in the context of a mergeable autogenerated operation
    #
    # @return whether the innermost operation conforms to the above criterion
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
          return true
        elsif op.type != :update then
          # not a save
          return false
        end
        # iterate to the scoping operation
        inner = op.subject
      end
      false
    end

    alias :to_s :print_class_and_id

    alias :inspect :to_s

    private

    ## Utility classes and methods, used by Query and Store mix-ins ##

    # Database CRUD operation.
    class Operation
      attr_reader :type, :subject, :attribute

      def initialize(type, subject, attribute=nil)
        @type = type
        @subject = subject
        @attribute = attribute
      end
    end

    # Performs the operation given by the given op symbol on obj by calling the block given to this method.
    # Returns the result of calling the block.
    # Valid op symbols are described in {Operation#initialize}.
    def perform(op, obj, attribute=nil)
      op_s = op.to_s.capitalize_first
      attr_s = " #{attribute}" if attribute
      ctxt_s = " in context #{print_operations}" unless @operations.empty?
      logger.info(">> #{op_s} #{obj.pp_s(:single_line)}#{attr_s}#{ctxt_s}...")
      @operations.push(Operation.new(op, obj, attribute))
      begin
        # perform the operation
        result = yield
      ensure
        # the operation is done
        @operations.pop
        # If this is a top-level operation, then clear the cache and transient set.
        if @operations.empty? then
          @cache.clear
          @transients.clear
        end
      end
      logger.info("<< Completed #{obj.qp}#{attr_s} #{op}.")
      result
    end
      
    # @return [Cache] a new object cache.
    def create_cache
      # JRuby alert - identifier is not a stable object when fetched from the database, i.e.:
      #   obj.identifier.equal?(obj.identifier) #=> false
      # This is probably an artifact of jRuby Numeric - Java Long conversion interaction
      # combined with hash access use of the eql? method. Work-around is to make a Ruby Integer.
      # the fetched object copier
      copier = Proc.new do |src|
        copy = src.copy
        logger.debug { "Fetched #{src.qp} copied to #{copy.qp}." }
        copy
      end
      # the fetched object cache
      Cache.new(copier) do |obj|
        raise ArgumentError.new("Can't cache object without identifier: #{obj}") unless obj.identifier
        obj.identifier.to_s.to_i
      end
    end
    
    # Initializes the default application service.
    def start_session
      raise DatabaseError.new('Application user option missing') if @user.nil?
      raise DatabaseError.new('Application password option missing') if @password.nil?
      # caCORE alert - obtaining a caCORE session instance mysteriously depends on referencing the application service first
      @def_persist_svc.app_service
      @session = ClientSession.instance()
      connect(@user, @password)
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
        logger.error("Login of #{user} unsuccessful - #{e.message}") and raise
      end
      logger.info("Connected to application server.")
    end
  end
end