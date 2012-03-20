require 'java'
require 'rdbi'
require 'rubygems'

class RDBI::Driver::JDBC < RDBI::Driver
  def initialize(*args)
    super Database, *args
  end
end

class RDBI::Driver::JDBC < RDBI::Driver

  SQL_TYPES = {
      1 => {:type => "CHAR",           :ruby_type => :default},
      2 => {:type => "NUMERIC",        :ruby_type => :decimal},
      3 => {:type => "DECIMAL",        :ruby_type => :decimal},
      4 => {:type => "INTEGER",        :ruby_type => :integer},
      5 => {:type => "SMALLINT",       :ruby_type => :integer},
      6 => {:type => "FLOAT",          :ruby_type => :decimal},
      7 => {:type => "REAL",           :ruby_type => :decimal},
      8 => {:type => "DOUBLE",         :ruby_type => :decimal},
      9 => {:type => "DATE",           :ruby_type => :date},
     10 => {:type => "TIME",           :ruby_type => :time},
     11 => {:type => "TIMESTAMP",      :ruby_type => :timestamp},
     12 => {:type => "VARCHAR",        :ruby_type => :default},
     13 => {:type => "BOOLEAN",        :ruby_type => :boolean},
     91 => {:type => "DATE",           :ruby_type => :date},
     92 => {:type => "TIME",           :ruby_type => :time},
     93 => {:type => "TIMESTAMP",      :ruby_type => :timestamp},
    100 => {:type => nil,              :ruby_type => :default},
     -1 => {:type => "LONG VARCHAR",   :ruby_type => :default},
     -2 => {:type => "BINARY",         :ruby_type => :default},
     -3 => {:type => "VARBINARY",      :ruby_type => :default},
     -4 => {:type => "LONG VARBINARY", :ruby_type => :default},
     -5 => {:type => "BIGINT",         :ruby_type => :integer},
     -6 => {:type => "TINYINT",        :ruby_type => :integer},
     -7 => {:type => "BIT",            :ruby_type => :default},
     -8 => {:type => "CHAR",           :ruby_type => :default},
    -10 => {:type => "BLOB",           :ruby_type => :default},
    -11 => {:type => "CLOB",           :ruby_type => :default},
  }

  class Database < RDBI::Database

    attr_accessor :handle

    def initialize(*args)
      super *args

      database = @connect_args[:database] || @connect_args[:dbname] ||
        @connect_args[:db]
      username = @connect_args[:username] || @connect_args[:user]
      password = @connect_args[:password] || @connect_args[:pass]
      
      # the driver class
      driver_class = @connect_args[:driver_class]
      raise DatabaseError.new('Missing JDBC driver class') unless driver_class
      clazz = java.lang.Class.forName(driver_class, true, JRuby.runtime.jruby_class_loader)
      java.sql.DriverManager.registerDriver(clazz.newInstance)

      @handle = java.sql.DriverManager.getConnection(
                  "#{database}",
                  username,
                  password
                )

      self.database_name = @handle.getCatalog
    end
    
    def disconnect
      @handle.rollback if @handle.getAutoCommit == false
      @handle.close
      super
    end

    def transaction(&block)
      raise RDBI::TransactionError, "Already in transaction" if in_transaction?
      @handle.setAutoCommit false
      @handle.setSavepoint
      super
      @handle.commit
      @handle.setAutoCommit true
    end

    def rollback
      @handle.rollback if @handle.getAutoCommit == false
      super
    end

    def commit
      @handle.commit if @handle.getAutoCommit == false
      super
    end

    def new_statement(query)
      Statement.new(query, self)
    end

    def table_schema(table_name)
      new_statement(
        "SELECT * FROM #{table_name} WHERE 1=2"
      ).new_execution[1]
    end

    def schema
      rs = @handle.getMetaData.getTables(nil, nil, nil, nil)
      tables = []
      while rs.next
        tables << table_schema(rs.getString(3))
      end
      tables
    end

    def ping
      !@handle.isClosed
    end

    def quote(item)
      case item
      when Numeric
        item.to_s
      when TrueClass
        "1"
      when FalseClass
        "0"
      when NilClass
        "NULL"
      else
        "'#{item.to_s}'"
      end
    end

  end

  class Cursor < RDBI::Cursor

    # TODO: update this to use real calls, not array
    # to get this working, we'll just build the array for now.
    def initialize(handle)
      super handle

      @index = 0
      @rs = []

      return if handle.nil?

      rs       = handle.getResultSet
      metadata = rs.getMetaData

      while rs.next
        data = []
        (1..metadata.getColumnCount).each do |n|
          data << parse_column(rs, n, metadata)
        end
        @rs << data
      end
    end

    def next_row
      return nil if last_row?
      val = @rs[@index]
      @index += 1
      val
    end

    def result_count
      @rs.size
    end

    def affected_count
      0
    end

    def first
      @rs.first
    end

    def last
      @rs.last
    end

    def rest
      @rs[@index..-1]
    end

    def all
      @rs
    end

    def fetch(count = 1)
      return [] if last_row?
      @rs[@index, count]
    end

    def [](index)
      @rs[index]
    end

    def last_row?
      @index == @rs.size
    end

    def empty?
      @rs.empty?
    end

    def rewind
      @index = 0
    end

    def size
      @rs.length
    end

    def finish
      @handle.close
    end

    def coerce_to_array
      @rs
    end

    private

    def parse_column(rs, n, metadata)
      return nil unless rs.getObject(n)
      case metadata.getColumnType(n)
      when java.sql.Types::BIT
        rs.getBoolean(n)
      when java.sql.Types::NUMERIC, java.sql.Types::DECIMAL
        case metadata.getScale(n)
        when 0
          rs.getLong(n)
        else
          rs.getDouble(n)
        end
      when java.sql.Types::DATE
        cal = calendar_for rs.getDate(n)

        Date.new(cal.get(java.util.Calendar::YEAR),
                 cal.get(java.util.Calendar::MONTH)+1,
                 cal.get(java.util.Calendar::DAY_OF_MONTH)
                )
      when java.sql.Types::TIME
        cal = calendar_for rs.getTime(n)

        Time.mktime(cal.get(java.util.Calendar::YEAR),
                    cal.get(java.util.Calendar::MONTH)+1,
                    cal.get(java.util.Calendar::DAY_OF_MONTH),
                    cal.get(java.util.Calendar::HOUR_OF_DAY),
                    cal.get(java.util.Calendar::MINUTE),
                    cal.get(java.util.Calendar::SECOND),
                    cal.get(java.util.Calendar::MILLISECOND) * 1000
                   )
      when java.sql.Types::TIMESTAMP
        cal = calendar_for rs.getTimestamp(n)

        DateTime.new(cal.get(java.util.Calendar::YEAR),
                     cal.get(java.util.Calendar::MONTH)+1,
                     cal.get(java.util.Calendar::DAY_OF_MONTH),
                     cal.get(java.util.Calendar::HOUR_OF_DAY),
                     cal.get(java.util.Calendar::MINUTE),
                     cal.get(java.util.Calendar::SECOND),
                     cal.get(java.util.Calendar::MILLISECOND) * 1000
                    )
      else
        rs.getObject(n)
      end
    end

    def calendar_for(col)
      cal = java.util.Calendar.getInstance
      cal.setTime(java.util.Date.new(col.getTime))
      cal
    end
  end

  class Statement < RDBI::Statement

    attr_accessor :handle

    def initialize(query, dbh)
      super

      @handle          = @dbh.handle.prepareStatement(query)
      @input_type_map  = build_input_type_map
      @output_type_map = build_output_type_map
    end

    def new_execution(*binds)
      apply_bindings(*binds)

      if @handle.execute
        metadata = @handle.getResultSet.getMetaData

        columns, tables = [], []

        (1..metadata.getColumnCount).each do |n|
          newcol = RDBI::Column.new
          newcol.name        = metadata.getColumnName(n).to_sym
          newcol.type        = SQL_TYPES[metadata.getColumnType(n)][:type]
          newcol.ruby_type   = SQL_TYPES[metadata.getColumnType(n)][:ruby_type]
          newcol.precision   = metadata.getPrecision(n)
          newcol.scale       = metadata.getScale(n)
          newcol.nullable    = metadata.isNullable(n) == 1 ? true : false
          newcol.table       = metadata.getTableName(n)
          #newcol.primary_key = false

          columns << newcol
        end
        tables = columns.map(&:table).uniq.reject{|t| t == ""}

        # primary_keys = Hash.new{|h,k| h[k] = []}
        # tables.each do |tbl|
        #   rs = @dbh.handle.getMetaData.getPrimaryKeys(nil, nil, tbl)
        #   while rs.next
        #     primary_keys[tbl] << rs.getString("COLUMN_NAME").to_sym
        #   end
        # end
        # columns.each do |col|
        #   col.primary_key = true if primary_keys[col.table].include? col.name
        # end
        return [
          Cursor.new(@handle),
          RDBI::Schema.new(columns, tables),
          @output_type_map
        ]
      end

      return [
        Cursor.new(nil),
        RDBI::Schema.new(nil, nil),
        @output_type_map
      ]
    end

    def finish
      @handle.close
      super
    end

    private

    def build_input_type_map
      input_type_map = RDBI::Type.create_type_hash(RDBI::Type::In)

      input_type_map[NilClass] = [TypeLib::Filter.new(
        proc{|o| o.nil?},
        proc{|o| java.sql.Types::VARCHAR}
      )]

      input_type_map[String] = [TypeLib::Filter.new(
        proc{|o| o.is_a? String},
        proc{|o| java.lang.String.new(o)}
      )]

      input_type_map[Date] = [TypeLib::Filter.new(
        proc{|o| o.is_a? Date},
        proc{|o|
          cal = apply_date_fields(java.util.Calendar.getInstance, o)
          java.sql.Date.new(cal.getTime.getTime)
        }
      )]

      input_type_map[Time] = [TypeLib::Filter.new(
        proc{|o| o.is_a? Time},
        proc{|o|
          cal = apply_time_fields(java.util.Calendar.getInstance, o)
          java.sql.Time.new(cal.getTime.getTime)
        }
      )]

      input_type_map[DateTime] = [TypeLib::Filter.new(
        proc{|o| o.is_a? DateTime},
        proc{|o|
          cal = apply_date_fields(java.util.Calendar.getInstance, o)
          cal = apply_time_fields(cal, o)
          java.sql.Timestamp.new(cal.getTime.getTime)
        }
      )]

      input_type_map
    end

    def build_output_type_map
      RDBI::Type.create_type_hash(RDBI::Type::Out)
    end

    def apply_bindings(*binds)
      @handle.clearParameters
      binds.each_with_index do |val, n|
        bind_param val, n+1
      end
    end

    def bind_param(val, n)
      case val
      when nil
        @handle.setNull(n, val)
      when String
        @handle.setString(n, val)
      when Java::JavaLang::String
        @handle.setString(n, val)
      when Fixnum
        @handle.setLong(n, val)
      when Java::JavaLang::Integer
        @handle.setLong(n, val)
      when Java::JavaLang::Character
        @handle.setLong(n, val)
      when Java::JavaLang::Short
        @handle.setLong(n, val)
      when Java::JavaLang::Long
        @handle.setLong(n, val)
      when Numeric
        @handle.setDouble(n, val)
      when Java::JavaLang::Float
        @handle.setDouble(n, val)
      when Java::JavaLang::Double
        @handle.setDouble(n, val)
      when Date
        @handle.setDate(n, val)
      when Time
        @handle.setTime(n, val)
      when DateTime
        @handle.setTimestamp(n, val)
      else
        @handle.setObject(n, val)
      end
    end

    def apply_date_fields(cal, date)
      cal.set(java.util.Calendar::YEAR,         date.year)
      cal.set(java.util.Calendar::MONTH,        date.month-1)
      cal.set(java.util.Calendar::DAY_OF_MONTH, date.day)
      cal
    end

    def apply_time_fields(cal, time)
      cal.set(java.util.Calendar::HOUR_OF_DAY, time.hour)
      cal.set(java.util.Calendar::MINUTE,      time.min)
      cal.set(java.util.Calendar::SECOND,      time.sec)
      cal.set(java.util.Calendar::MILLISECOND, time.strftime("%L").to_i)
      cal
    end
  end
end
