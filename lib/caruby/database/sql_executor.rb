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
    # The default database host is the application :host property value, which in turn
    # defaults to +localhost+.
    #
    # The default database type is +mysql+. The optional :database_port property overrides
    # the default port for the database type.
    #
    # The default database driver is +jdbc:mysql+ for MySQL, +Oracle+ for Oracle.
    # The default database driver class is +com.mysql.jdbc.Driver+ for MySQL,
    # +oracle.jdbc.OracleDriver+ for Oracle.
    #
    # @param [Hash] opts the connect options
    # @option opts [String] :database the mandatory database name
    # @option opts [String] :database_user the mandatory database username (not the application login name)
    # @option opts [String] :database_password the optional database password (not the application login password)
    # @option opts [String] :database_host the optional database host
    # @option opts [Integer] :database_port the optional database port number
    # @option opts [String] :database_type the optional DBI database type, e.g. +mysql+
    # @option opts [String] :database_driver the optional DBI connect driver string, e.g. +jdbc:mysql+
    # @option opts [String] :database_driver_class the optional DBI connect driver class name
    # @raise [CaRuby::ConfigurationError] if an option is invalid
    def initialize(opts)
      if opts.empty? then
        raise CaRuby::ConfigurationError.new("The caRuby database connection properties were not found.") 
      end
      app_host = Options.get(:host, opts, 'localhost')
      db_host = Options.get(:database_host, opts, app_host)
      db_type = Options.get(:database_type, opts, 'mysql')
      db_driver = Options.get(:database_driver, opts) { default_driver_string(db_type) }
      db_port = Options.get(:database_port, opts) { default_port(db_type) }
      db_name = Options.get(:database, opts) { raise_missing_option_exception(:database) }
      @address = "dbi:#{db_driver}://#{db_host}:#{db_port}/#{db_name}"
      @username = Options.get(:database_user, opts) { raise_missing_option_exception(:database_user) }
      @password = Options.get(:database_password, opts)
      @driver_class = Options.get(:database_driver_class, opts, default_driver_class(db_type))
      # The effective connection options.
      eff_opts = {
        :database => db_name,
        :database_host => db_host,
        :database_user => @username,
        :database_type => db_type,
        :database_port => db_port,
        :database_driver => db_driver,
        :database_driver_class => @driver_class,
        :address => @address
      }
      logger.debug { "Database connection parameters (excluding password): #{eff_opts.qp}" }
    end

    # Connects to the database, yields the DBI handle to the given block and disconnects.
    #
    # @return [Array] the execution result
    def execute
      DBI.connect(@address, @username, @password, 'driver'=> @driver_class) { |dbh| yield dbh }
    end

    private
    
    MYSQL_DRIVER_CLASS_NAME = 'com.mysql.jdbc.Driver'
    
    ORACLE_DRIVER_CLASS_NAME = 'oracle.jdbc.OracleDriver'

    def default_driver_string(db_type)
      case db_type.downcase
        when 'mysql' then 'Jdbc:mysql'
        when 'oracle' then 'Oracle'
        else raise CaRuby::ConfigurationError.new("Default database connection driver string could not be determined for database type #{db_type}")
      end
    end
    
    def default_driver_class(db_type)
      case db_type.downcase
        when 'mysql' then MYSQL_DRIVER_CLASS_NAME
        when 'oracle' then ORACLE_DRIVER_CLASS_NAME
        else raise CaRuby::ConfigurationError.new("Default database connection driver class could not be determined for database type #{db_type}")
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
      raise CaRuby::ConfigurationError.new("Database connection property not found: #{option}")
    end
  end
end