require 'jinx/helpers/options'
require 'caruby/rdbi/driver/jdbc'

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
    # The default database URI is +dbi:+_db_driver_+://+_db_host_+:+_db_port_+/+_db_name_.
    #
    # @param [Hash] opts the connect options
    # @option opts [String] :database the mandatory database name
    # @option opts [String] :database_user the mandatory database username (not the application login name)
    # @option opts [String] :database_password the optional database password (not the application login password)
    # @option opts [String] :database_host the optional database host
    # @option opts [Integer] :database_port the optional database port number
    # @option opts [Integer] :database_port the optional database port number
    # @option opts [String] :database_driver the optional DBI connect driver string, e.g. +jdbc:mysql+
    # @option opts [String] :database_url the optional database connection URL
    # @option opts [String] :database_driver_class the optional DBI connect driver class name
    # @raise [CaRuby::ConfigurationError] if an option is invalid
    def initialize(opts)
      if opts.empty? then
        Jinx.fail(CaRuby::ConfigurationError, "The caRuby database connection properties were not found.") 
      end
      app_host = Options.get(:host, opts, 'localhost')
      db_host = Options.get(:database_host, opts, app_host)
      db_type = Options.get(:database_type, opts, 'mysql')
      db_driver = Options.get(:database_driver, opts) { default_driver_string(db_type) }
      db_port = Options.get(:database_port, opts) { default_port(db_type) }
      db_name = Options.get(:database, opts) { raise_missing_option_exception(:database) }
      @db_url = Options.get(:database_url, opts) { "#{db_driver}://#{db_host}:#{db_port}/#{db_name}" }
      @dbi_url = 'dbi:' + @db_url
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
        :database_url => @db_url
      }
      logger.debug { "Database connection parameters (excluding password): #{eff_opts.qp}" }
    end

    # Connects to the database, yields the DBI handle to the given block and disconnects.
    #
    # @yield [dbh] the transaction statements
    # @yieldparam [RDBI::Database] dbh the database handle
    def execute
      RDBI.connect(:JDBC, :database => @db_url, :user => @username, :password => @password, :driver_class=> @driver_class) do |dbh|
        yield dbh
      end
    end

    # Runs the given query.
    #
    # @param [String] sql the SQL to execute
    # @param [Array] args the SQL bindings
    # @return [Array] the query result
    def query(sql, *args)
      fetched = nil
      execute do |dbh|
        res = dbh.execute(sql, *args)
        fetched = res.fetch(:all)
        res.finish
      end
      fetched
    end

    # Runs the given modification SQL or block as a transaction.
    #
    # @param [String] sql the SQL to execute
    # @param [Array] args the SQL bindings
    # @yield [dbh] the transaction statements
    # @yieldparam [RDBI::Database] dbh the database handle
    def transact(sql=nil, *args)
      return transact { |dbh| dbh.execute(sql, *args) } if sql
      execute do |dbh|
        dbh.transaction { yield dbh }
      end
    end

    private
    
    MYSQL_DRIVER_CLASS_NAME = 'com.mysql.jdbc.Driver'
    
    ORACLE_DRIVER_CLASS_NAME = 'oracle.jdbc.OracleDriver'

    def default_driver_string(db_type)
      case db_type.downcase
        when 'mysql' then 'Jdbc:mysql'
        when 'oracle' then 'Oracle'
        else Jinx.fail(CaRuby::ConfigurationError, "Default database connection driver string could not be determined for database type #{db_type}")
      end
    end
    
    def default_driver_class(db_type)
      case db_type.downcase
        when 'mysql' then MYSQL_DRIVER_CLASS_NAME
        when 'oracle' then ORACLE_DRIVER_CLASS_NAME
        else Jinx.fail(CaRuby::ConfigurationError, "Default database connection driver class could not be determined for database type #{db_type}")
      end
    end

    def default_port(db_type)
      case db_type.downcase
        when 'mysql' then 3306
        when 'oracle' then 1521
        else Jinx.fail(CaRuby::ConfigurationError, "Default database connection port could not be determined for database type #{db_type}")
      end
    end

    def raise_missing_option_exception(option)
      Jinx.fail(CaRuby::ConfigurationError, "Database connection property not found: #{option}")
    end
  end
end