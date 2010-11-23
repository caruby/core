require 'rubygems'
gem 'dbi'

require 'dbi'
require 'caruby/util/options'
require 'caruby/util/log'
require 'caruby/domain/properties'

module CaRuby
  # SQLExecutor executes an SQL statement against the database.
  # Use of this class requires the dbi gem.
  # SQLExecutor is an auxiliary utility class and is not used by the rest of the CaRuby API.
  class SQLExecutor
    # Creates a new SQLExecutor with the given options.
    #
    # The default :database_host is the application :host property value, which in turn
    # defaults to 'localhost'.
    #
    # The default :database_type is 'mysql'. The optional :database_port property overrides
    # the default port for the database type.
    #
    # The default :database_driver is 'jdbc:mysql' for MySQL or 'Oracle' for Oracle.
    #
    # @option options [String] :database_host the database host
    # @option options [String] :database the database name
    # @option options [Integer] :database_port the database password (not the application login password)
    # @option options [String] :database_type the DBI database type, e.g. +mysql+
    # @option options [String] :database_driver the DBI connect driver string, e.g. +jdbc:mysql+
    # @option options [String] :database_user the database username (not the application login name)
    # @option options [String] :database_password the database password (not the application login password)
    # Raises CaRuby::ConfigurationError if an option is invalid.
    def initialize(options)
      app_host = Options.get(:host, options, "localhost")
      db_host = Options.get(:database_host, options, app_host)
      db_type = Options.get(:database_type, options, "mysql")
      db_driver = Options.get(:database_driver, options) { default_driver_string(db_type) }
      db_port = Options.get(:database_port, options) { default_port(db_type) }
      db_name = Options.get(:database, options) { raise_missing_option_exception(:database) }
      @address = "dbi:#{db_driver}://#{db_host}:#{db_port}/#{db_name}"
      @username = Options.get(:database_user, options) { raise_missing_option_exception(:database_user) }
      @password = Options.get(:database_password, options) { raise_missing_option_exception(:database_password) }
    end

    # Connects to the database, yields the DBI handle to the given block and disconnects.
    # Returns the execution result.
    def execute
      logger.debug { "Connecting to database with user #{@username}, address #{@address}..." }
      result = DBI.connect(@address, @username, @password, "driver"=>"com.mysql.jdbc.Driver") { |dbh| yield dbh }
      logger.debug { "Disconnected from the database." }
      result
    end

    private

    def default_driver_string(db_type)
      case db_type.downcase
      when 'mysql' then 'jdbc:mysql'
      when 'oracle' then 'Oracle'
      else raise CaRuby::ConfigurationError.new("Default database connection driver string could not be determined for database type #{db_type}")
      end
    end

    def default_port(db_type)
      case db_type.downcase
      when 'mysql' then 3306
      when 'oracle' then 1521
      else raise CaRuby::ConfigurationError.new("Default database connection port could not be determined for database type #{db_type}")
      end
    end

    def raise_missing_option_exception(option)
      raise CaRuby::ConfigurationError.new("database connection property not found: #{option}")
    end
  end
end