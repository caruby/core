require 'jinx/helpers/stopwatch'
require 'jinx/migration/migrator'

module CaRuby
  class Migrator < Jinx::Migrator
    # Creates a new Migrator with the given options.
    #
    # This migrator must include sufficient information to build a well-formed migration target object.
    # For example, if the target object is a new SpecimenCollectionGroup, then the migration must also be
    # able to build that SCG's CollectionProtocolRegistration. The CPR in turn must either exist in the
    # database or the migration must build a Participant and a CollectionProtocol.
    # 
    # @option (see Jinx::Migrator#initialize)
    # @option opts [Database] :database the target application database
    def initialize(opts={})
      super
      @database = opts[:database]
    end
    
    # Imports this migrator's file into the database with the given connect options.
    # This method creates or updates the domain objects mapped from the import source.
    # If a block is given to this method, then the block is called on each stored
    # migration target object.
    #
    # If the +:create+ option is set, then an input record for a target object which already
    # exists in the database is noted in a debug log message and ignored rather than updated.
    #
    # @yield (see #migrate)
    # @yieldparam (see #migrate)
    # @return (see #migrate)
    def migrate_to_database(&block)
      # migrate with save
      tm = Jinx::Stopwatch.measure { execute_save(&block) }.elapsed
      logger.debug { format_migration_time_log_message(tm) }
    end
    
    private

    # {#migrate} with a {#save} block on the migration target. Each migrated object
    # is created, if necessary, after the target save.
    def execute_save
      if @database.nil? then
        Jinx.fail(MigrationError, "Migrator cannot save records since the database option was not specified.")
      end
      @database.open do |db|
        migrate do |tgt, rec|
          save(tgt, db)
          # Ensure that each migrated object is created if necessary.
          @migrated.each do |obj|
            next if obj.identifier
            logger.debug { "The migrator is saving the migrated #{obj}..." }
            save(obj, db)
            logger.debug { "The migrator saved the migrated #{obj}." }
          end
          yield(tgt, rec) if block_given?
          db.clear
        end
      end
    end

    # @param [Resource] obj the domain object to save in the database
    # @return [Resource, nil] obj if the save is successful, nil otherwise
    def save(obj, database)
      if @create then
        logger.debug { "Migrator creating #{obj}..." }
        database.create(obj)
        logger.debug { "Migrator created #{obj}." }
      else
        logger.debug { "Migrator saving #{obj}..." }
        database.save(obj)
        logger.debug { "Migrator saved #{obj}." }
      end
    end

    # @return [String] a log message for the given migration time in seconds
    def format_migration_time_log_message(time)
      # the database execution time
      dt = @database.execution_time
      if time > 120 then
        time /= 60
        dt /= 60
        unit = "minutes"
      else
        unit = "seconds"
      end
      "Migration took #{'%.2f' % time} #{unit}, of which #{'%.2f' % dt} were database operations."
    end
  end
end
    