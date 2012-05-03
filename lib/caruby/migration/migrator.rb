require 'jinx/helpers/stopwatch'
require 'jinx/migration/migrator'

module CaRuby
  class Migrator < Jinx::Migrator
    # Creates a new Migrator with the given options.
    #
    # The migration configuration must provide sufficient information to build a well-formed migration
    # target object. For example, if the target object is a new +CaTissue::SpecimenCollectionGroup+,
    # then the migrator must build that SCG's required +CollectionProtocolRegistration+. The CPR in
    # turn must either exist in the database or the migrator must build the required CPR
    # +participant+ and +collection_protocol+.
    # 
    # @option (see Jinx::Migrator#initialize)
    # @option opts [Database] :database the target application database
    # @see #migrate_to_database
    def initialize(opts={})
      super
      @database = opts[:database]
    end
    
    # Imports this migrator's file into the database with the given connect options.
    # This method creates or updates the domain objects mapped from the migration source.
    # If a block is given to this method, then the block is called on each migrated
    # target object.
    #
    # The target object is saved in the database. Every referenced migrated object is created,
    # if necessary. Finally, a migration target owner object is created, if necessary.
    #
    # For example, suppose a migration configuration specifies the following:
    # * the target is a +CaTissue::SpecimenCollectionGroup+
    # * the field mapping specifies a +Participant+ MRN,
    # * the defaults specify a +CollectionProtocol+ title and a +Site+ name
    #
    # The migrator attempts to fetch the protocol and site from the database. If they do not
    # exist, then they are created. In order to create the protocol and site, the migration
    # configuration must specify sufficient information to validate the objects before creation,
    # as described in {#initialize}. Finally, the SCG +CollectionProtocolRegistration+ owner
    # is created. This CPR references the migration protocol and site.
    #
    # If the +:create+ option is set, then an input record for a target object which already
    # exists in the database is noted in a debug log message and ignored rather than updated.
    #
    # @yield [target, row] operates on the migration target
    # @yieldparam [Resource] target the migrated target domain object
    # @yieldparam [{Symbol => Object}] row the migration source record
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
        raise MigrationError.new("Migrator cannot save records since the database option was not specified.")
      end
      @database.open do |db|
        migrate do |tgt, rec|
          # Save the target object.
          save(tgt, db)
          # Ensure that each migrated object is created if necessary.
          @migrated.each { |obj| create(obj, db) unless db.exists?(obj) }
          yield(tgt, rec) if block_given?
          db.clear
        end
      end
    end

    # @param [Resource] obj the domain object to save in the database
    # @return [Resource, nil] obj if the save is successful, nil otherwise
    def save(obj, database)
      if @create then
        create(obj, database)
      else
        logger.debug { "Migrator saving #{obj}..." }
        database.save(obj)
        logger.debug { "Migrator saved #{obj}." }
      end
    end

    # @param [Resource] obj the domain object to create in the database
    # @return [Resource, nil] obj if the create is successful, nil otherwise
    def create(obj, database)
      logger.debug { "Migrator creating #{obj}..." }
      database.create(obj)
      logger.debug { "Migrator created #{obj}." }
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
    