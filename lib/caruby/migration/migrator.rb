# load the required gems
require 'rubygems'

# the Units of Measurement gem
gem 'uom'

require 'enumerator'
require 'date'
require 'uom'
require 'caruby/csv/csvio'
require 'caruby/util/class'
require 'caruby/util/log'
require 'caruby/util/inflector'
require 'caruby/util/options'
require 'caruby/util/pretty_print'
require 'caruby/util/properties'
require 'caruby/util/collection'
require 'caruby/migration/migratable'

module CaRuby
  class MigrationError < RuntimeError; end

  # Migrates a CSV extract to a caBIG application.
  class Migrator
    include Enumerable

    # Creates a new Migrator.
    #
    # @param [{Symbol => Object}] opts the migration options
    # @option opts [String] :database required application {Database}
    # @option opts [String] :target required target domain class
    # @option opts [<String>, String] :mapping required input field => caTissue attribute mapping file(s)
    # @option opts [<String>, String] :defaults optional caTissue attribute => value default mapping file(s)
    # @option opts [<String>, String] :filters optional caTissue attribute input value => caTissue value filter file(s)
    # @option opts [String] :input required source file to migrate
    # @option opts [<String>, String] :shims optional shim file(s) to load
    # @option opts [String] :unique ensures that migrated objects which include the {Resource::Unique}
    # @option opts [String] :create optional flag indicating that existing target objects are ignored
    # @option opts [String] :bad optional invalid record file
    # @option opts [Integer] :offset zero-based starting source record number to process (default 0)
    # @option opts [Boolean] :quiet suppress output messages
    # @option opts [Boolean] :verbose print progress
    def initialize(opts)
      @rec_cnt = 0
      parse_options(opts)
      build
    end
    
    # Imports this migrator's file into the database with the given connect options.
    # This method creates or updates the domain objects mapped from the import source.
    # If a block is given to this method, then the block is called on each stored
    # migration target object.
    #
    # If the +:create+ option is set, then an input record for a target object which already
    # exists in the database is noted in a debug log message and ignored rather than updated.
    #
    # @yield [target] operation performed on the migration target
    # @yieldparam [Resource] target the migrated target domain object
    def migrate_to_database(&block)
      # migrate with save
      tm = Stopwatch.measure { execute_save(&block) }.elapsed
      logger.debug { format_migration_time_log_message(tm) }
    end

    # Imports this migrator's CSV file and calls the required block on each migrated target
    # domain object.
    #
    # @yield [target] operation performed on the migration target
    # @yieldparam [Resource] target the migrated target domain object
    def migrate(&block)
      raise MigrationError.new("The caRuby Migrator migrate block is missing") unless block_given?
      migrate_rows(&block)
    end

    alias :each :migrate

    private
    
    REGEXP_PAT = /^\/(.*[^\\])\/([inx]+)?$/

    # Class {#migrate} with a {#save} block.
    def execute_save
      if @database.nil? then
        raise MigrationError.new("Migrator cannot save records since the database option was not specified.")
      end
      @database.open do |db|
        migrate do |target|
          save(target, db)
          yield target if block_given?
          db.clear
        end
      end
    end

    # @return a log message String for the given migration time in seconds
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

    def parse_options(opts)
      @fld_map_files = opts[:mapping]
      raise MigrationError.new("Migrator missing required field mapping file parameter") if @fld_map_files.nil?
      @def_files = opts[:defaults]
      @filter_files = opts[:filters]
      @shims = opts[:shims] ||= []
      @offset = opts[:offset] ||= 0
      @input = Options.get(:input, opts)
      raise MigrationError.new("Migrator missing required source file parameter") if @input.nil?
      @database = opts[:database]
      @target_class = opts[:target]
      raise MigrationError.new("Migrator missing required target class parameter") if @target_class.nil?
      @bad_rec_file = opts[:bad]
      @create = opts[:create]
      logger.info("Migration options: #{printable_options(opts).pp_s}.")
      # flag indicating whether to print a progress monitor
      @print_progress = opts[:verbose]
    end
    
    def printable_options(opts)
      popts = opts.reject { |option, value| value.nil_or_empty? }
      # The target class should be a simple class name rather than the class metadata.
      popts[:target] = popts[:target].qp if popts.has_key?(:target)
      popts
    end

    def build
      # the current source class => instance map
      raise MigrationError.new("No file to migrate") if @input.nil?

      # make a CSV loader which only converts input fields corresponding to non-String attributes
      @loader = CsvIO.new(@input, &method(:convert))
      logger.debug { "Migration data input file #{@input} headers: #{@loader.headers.qp}" } 
      
      # add shim modifiers
      load_shims(@shims)

      # create the class => path => default value hash
      @def_hash = @def_files ? load_defaults_files(@def_files) : {}
      # create the class => path => default value hash
      @filter_hash = @filter_files ? load_filter_files(@filter_files) : {}
      # create the class => path => header hash
      fld_map = load_field_map_files(@fld_map_files)
      # create the class => paths hash
      @cls_paths_hash = create_class_paths_hash(fld_map, @def_hash)
      # create the path => class => header hash
      @header_map = create_header_map(fld_map)
      # add missing owner classes (copy the keys rather than using each_key since the hash is updated)
      @owners = Set.new
      @cls_paths_hash.keys.each { |klass| add_owners(klass) }
      # order the creatable classes by dependency, owners first, to smooth the migration process
      @creatable_classes = @cls_paths_hash.keys.sort! { |klass, other| other.depends_on?(klass) ? -1 : (klass.depends_on?(other) ? 1 : 0) }
      @creatable_classes.each do |klass|
        if klass.abstract? then
          raise MigrationError.new("Migrator cannot create the abstract class #{klass}; specify a subclass instead in the mapping file.")
        end
      end
      
      # print the maps
      print_hash = LazyHash.new { Hash.new }
      @cls_paths_hash.each do |klass, paths|
        print_hash[klass.qp] = paths.map { |path| {path.map { |attr_md| attr_md.to_sym  }.join('.') => @header_map[path][klass] } }
      end
      logger.info { "Migration paths:\n#{print_hash.pp_s}" }
      logger.info { "Migration creatable classes: #{@creatable_classes.qp}." }
      unless @def_hash.empty? then logger.info { "Migration defaults: #{@def_hash.qp}." } end
      
      # the class => attribute migration methods hash
      create_migration_method_hashes
      
      # Collect the String input fields for the custom CSVLoader converter.
      @nonstring_headers = Set.new
      logger.info("Migration attributes:")
      @header_map.each do |path, cls_hdr_hash|
        attr_md = path.last
        cls_hdr_hash.each do |klass, hdr|
          type_s = attr_md.type ? attr_md.type.qp : 'Object'
          logger.info("  #{hdr} => #{klass.qp}.#{path.join('.')} (#{type_s})")
        end
        @nonstring_headers.merge!(cls_hdr_hash.values) if attr_md.type != Java::JavaLang::String
      end
    end
    
    # Converts the given input field value as follows:
    # * if the info header is a String field, then return the value unchanged
    # * otherwise, if the value is a case-insensitive match for +true+ or +false+, then convert
    #   the value to the respective Boolean
    # * otherwise, return nil which will delegate to the generic CsvIO converter
    # @param (see CsvIO#convert)
    # @yield (see CsvIO#convert)
    def convert(value, info)
      @nonstring_headers.include?(info.header) ? convert_boolean(value) : value
    end
    
    # @param [String] value the input value
    # @return [Boolean, nil] the corresponding boolean, or nil if none
    def convert_boolean(value)
      case value
        when /true/i then true
        when /false/i then false
      end
    end
    
    # Adds missing owner classes to the migration class path hash (with empty paths)
    # for the  the given migration class.
    #
    # @param [Class] klass the migration class
    def add_owners(klass)
      owner = missing_owner_for(klass) || return
      logger.debug { "Migrator adding #{klass.qp} owner #{owner}" }
      @owners << owner
      @cls_paths_hash[owner] = Array::EMPTY_ARRAY
      add_owners(owner)
    end
    
    # @param [Class] klass the migration class
    # @return [Class, nil] the missing class owner, if any
    def missing_owner_for(klass)
      # check for an owner among the current migration classes
      return if klass.owners.any? do |owner|
        @cls_paths_hash.detect_key { |other| other <= owner }
      end
      # find the first non-abstract candidate owner
      klass.owners.detect { |owner| not owner.abstract? }
    end

    # Creates the class => +migrate_+_<attribute>_ hash for the given klasses.
    def create_migration_method_hashes
      # the class => attribute => migration filter hash
      @attr_flt_hash = {}
      customizable_class_attributes.each do |klass, attr_mds|
        flts = migration_filters(klass, attr_mds) || next
        @attr_flt_hash[klass] = flts
      end

      # print the migration shim methods
      unless @attr_flt_hash.empty? then
        printer_hash = LazyHash.new { Array.new }
        @attr_flt_hash.each do |klass, hash|
          mths = hash.values.select { |flt| Symbol === flt }
          printer_hash[klass.qp] = mths unless mths.empty?
        end
        logger.info("Migration shim methods: #{printer_hash.pp_s}.") unless printer_hash.empty?
      end
    end

    # @return the class => attributes hash for terminal path attributes which can be customized by +migrate_+ methods
    def customizable_class_attributes
      # The customizable classes set, starting with creatable classes and adding in
      # the migration path terminal attribute declarer classes below.
      klasses = @creatable_classes.to_set
      # the class => path terminal attributes hash
      cls_attrs_hash = LazyHash.new { Set.new }
      # add each path terminal attribute and its declarer class
      @cls_paths_hash.each_value do |paths|
        paths.each do |path|
          attr_md = path.last
          type = attr_md.declarer
          klasses << type
          cls_attrs_hash[type] << attr_md
        end
      end
      
      # Merge each redundant customizable superclass into its concrete customizable subclasses. 
      klasses.dup.each do |cls|
        redundant = false
        klasses.each do |other|
          # cls is redundant if it is a superclass of other
          redundant = other < cls
          if redundant then
            cls_attrs_hash[other].merge!(cls_attrs_hash[cls])
          end
        end
        # remove the redundant class
        if redundant then
          cls_attrs_hash.delete(cls)
          klasses.delete(cls)
        end
      end
      
      cls_attrs_hash
    end

    # Discovers methods of the form +migrate+__attribute_ implemented for the paths
    # in the given class => paths hash the given klass. The migrate method is called
    # on the input field value corresponding to the path.
    def migration_filters(klass, attr_mds)
      # the attribute => migration method hash
      mth_hash = attribute_method_hash(klass, attr_mds)
      proc_hash = attribute_proc_hash(klass, attr_mds)
      return if mth_hash.empty? and proc_hash.empty?

      # for each class path terminal attribute metadata, add the migration filters
      # to the attribute metadata => filter hash
      attr_mds.to_compact_hash do |attr_md|
        # the filter proc
        proc = proc_hash[attr_md.to_sym]
        # the migration shim method
        mth = mth_hash[attr_md.to_sym]
        if mth then
          if proc then
            Proc.new do |obj, value, row|
              # filter the value
              fval = proc.call(value)
              # call the migration method on the filtered value
              obj.send(mth, fval, row) unless fval.nil?
            end
          else
            # call the migration method
            Proc.new { |obj, value, row| obj.send(mth, value, row) }
          end
        elsif proc then
          # call the filter
          Proc.new { |obj, value, row| proc.call(value) }
        end
      end
    end
    
    def attribute_method_hash(klass, attr_mds)
      # the migrate methods, excluding the Migratable migrate_references method
      mths = klass.instance_methods(true).select { |mth| mth =~ /^migrate.(?!references)/ }
      # the attribute => migration method hash
      mth_hash = {}
      mths.each do |mth|
        # the attribute suffix, e.g. name for migrate_name or Name for migrateName
        suffix = /^migrate(_)?(.*)/.match(mth).captures[1]
        # the attribute name
        attr_nm = suffix[0, 1].downcase + suffix[1..-1]
        # the attribute for the name, or skip if no such attribute
        attr = klass.standard_attribute(attr_nm) rescue next
        # associate the attribute => method
        mth_hash[attr] = mth
      end
      mth_hash
    end
    
    # @return [Attribute => {Object => Object}] the filter migration methods
    def attribute_proc_hash(klass, attr_mds)
      hash = @filter_hash[klass]
      if hash.nil? then return Hash::EMPTY_HASH end
      proc_hash = {}
      attr_mds.each do |attr_md|
        flt = hash[attr_md.to_sym] || next
        proc_hash[attr_md.to_sym] = to_filter_proc(flt)
      end
      logger.debug { "Migration filters loaded for #{klass.qp} #{proc_hash.keys.to_series}." }
      proc_hash
    end
    
    # Builds a proc that filters the input value. The config filter mapping entry is one of the following:
    #   * literal: literal
    #   * regexp: literal
    #   * regexp: template
    #
    # The regexp template can include match references (+$1+, +$2+, etc.) corresponding to the regexp captures.
    # If the input value equals a literal, then the mapped literal is returned. Otherwise, if the input value
    # matches a regexp, then the mapped transformation is returned after reference substitution. Otherwise,
    # the input value is returned unchanged.
    #
    # For example, the config:
    #   /(\d{1,2})\/x\/(\d{1,2})/: $1/1/$2
    #   n/a: ~
    # converts the input value as follows:
    #   3/12/02 => 3/12/02 (no match)
    #   5/x/04 => 5/1/04
    #   n/a => nil 
    #
    # @param [{Object => Object}] filter the config value mapping
    # @return [Proc] the filter migration block
    # @raise [MigrationError] if the filter includes a regexp option other than +i+ (case-insensitive)
    def to_filter_proc(filter)
      # Split the filter into a straight value => value hash and a pattern => value hash.
      ph, vh = filter.split { |k, v| k =~ REGEXP_PAT }
      # The Regexp => value hash is built from the pattern => value hash.
      reh = {}
      ph.each do |k, v|
        # The /pattern/opts string is parsed to the pattern and options.
        pat, opt = REGEXP_PAT.match(k).captures
        # Convert the regexp i option character to a Regexp initializer parameter.
        reopt = if opt then
          case opt
            when 'i' then Regexp::IGNORECASE
            else raise MigrationError.new("Migration value filter regular expression #{k} qualifier not supported: expected 'i', found '#{opt}'")
          end
        end
        # the Regexp object
        re = Regexp.new(pat, reopt)
        # The regexp value can include match references ($1, $2, etc.). In that case, replace the $
        # match reference with a %s print reference, since the filter formats the matching input value.
        reh[re] = String === v ? v.gsub(/\$\d/, '%s') : v
      end
      # The new proc matches preferentially on the literal value, then the first matching regexp.
      # If no match on either a literal or a regexp, then the value is preserved.
      Proc.new do |value|
        if vh.has_key?(value) then
          vh[value]
        else
          # The first regex which matches the value.
          regexp = reh.detect_key { |re| value =~ re }
          # If there is a match, then apply the filter to the match data.
          # Otherwise, pass the value through unmodified.
          if regexp then
            v = reh[regexp]
            String === v ? v % $~.captures : v
          else
            value
          end
        end
      end
    end

    # Loads the shim files.
    #
    # @param [<String>, String] files the file or file array
    def load_shims(files)
      logger.debug { "Loading shims with load path #{$:.pp_s}..." }
      files.enumerate do |file|
        # load the file
        begin
          require file
      rescue Exception => e
          logger.error("Migrator couldn't load shim file #{file} - #{e}.")
          raise
        end
        logger.info { "Migrator loaded shim file #{file}." }
      end
    end

    # Migrates all rows in the input.
    #
    # @yield (see #migrate)
    # @yieldparam (see #migrate)
    def migrate_rows
      # open an CSV output for bad records if the option is set
      if @bad_rec_file then
        @loader.trash = @bad_rec_file
        logger.info("Unmigrated records will be written to #{File.expand_path(@bad_rec_file)}.")
      end
      @rec_cnt = mgt_cnt = 0
      logger.info { "Migrating #{@input}..." }
      @loader.each do |row|
        # the one-based current record number
        rec_no = @rec_cnt + 1
        # skip if the row precedes the offset option
        @rec_cnt += 1 && next if @rec_cnt < @offset
        begin
          # migrate the row
          logger.debug { "Migrating record #{rec_no}..." }
          target = migrate_row(row)
          # call the block on the migrated target
          if target then
            logger.debug { "Migrator built #{target} with the following content:\n#{target.dump}" }
            yield target
          end
        rescue Exception => e
          trace = e.backtrace.join("\n")
          logger.error("Migration error on record #{rec_no} - #{e.message}:\n#{trace}")
          raise unless @bad_file
        end
        if target then
          # replace the log message below with the commented alternative to detect a memory leak
          logger.debug { "Migrated record #{rec_no}." }
          #memory_usage = `ps -o rss= -p #{Process.pid}`.to_f / 1024 # in megabytes
          #logger.debug { "Migrated rec #{@rec_cnt}; memory usage: #{sprintf("%.1f", memory_usage)} MB." }
          if @print_progress then print_progress(mgt_cnt) end
          mgt_cnt += 1
          # clear the migration state
          clear(target)
        else
          # If there is a bad file then warn, reject and continue. Otherwise, bail.
          if @bad_rec_file then
            logger.warn("Migration not performed on record #{rec_no}.")
            @loader.reject(row)
          else
            raise MigrationError.new("Migration not performed on record #{rec_no}")
          end
        end
        # Bump the record count.
        @rec_cnt += 1
      end
      logger.info("Migrated #{mgt_cnt} of #{@rec_cnt} records.")
    end
    
    # Prints a +\++ progress indicator to stdout if the count parameter is divisible by ten.
    #
    # @param [Integer] count the progress step count
    def print_progress(count)
      if count % 720 then puts end
      if count % 10 == 0 then puts "+" else print "+" end
    end

    # Clears references to objects allocated for migration of a single row into the given target.
    # This method does nothing. Subclasses can override.
    #
    # This method is overridden by subclasses to clear the migration state to conserve memory,
    # since this migrator should consume O(1) rather than O(n) memory for n migration records.
    def clear(target)
    end

    # Imports the given CSV row into a target object.
    #
    # @param [{Symbol => Object}] row the input row field => value hash
    # @return the migrated target object if the migration is valid, nil otherwise
    def migrate_row(row)
      # create an instance for each creatable class
      created = Set.new
      migrated = @creatable_classes.map { |klass| create(klass, row, created) }
      # migrate each object from the input row
      created.each { |obj| obj.migrate(row, migrated) }
      valid = migrate_valid_references(row, migrated)
      # the target object
      target = valid.detect { |obj| @target_class === obj } || return
      logger.debug { "Migrated target #{target}." }
      target
    end
    
    # Sets the migration references for each valid migrated object.
    #
    # @param [Array] the migrated objects
    # @return [Array] the valid migrated objects
    def migrate_valid_references(row, migrated)
      # Split the valid and invalid objects. The iteration is in reverse dependency order,
      # since invalidating a dependent can invalidate the owner.
      valid, invalid = migrated.transitive_closure(:dependents).reverse.partition do |obj|
        if migration_valid?(obj) then
          obj.migrate_references(row, migrated, @attr_flt_hash[obj.class])
          true
        else
          obj.class.owner_attributes.each { |attr| obj.clear_attribute(attr) }
          false
        end
      end
      
      # Go back through the valid objects in dependency order to invalidate dependents
      # whose owner is invalid.
      valid.reverse.each do |obj|
        unless owner_valid?(obj, valid, invalid) then
          invalid << valid.delete(obj)
          logger.debug { "Invalidated migrated #{obj} since it does not have a valid owner." }
        end
      end
      
      # Go back through the valid objects in reverse dependency order to invalidate owners
      # created only to hold a dependent which was subsequently invalidated.
      valid.reject do |obj|
        if @owners.include?(obj.class) and obj.dependents.all? { |dep| invalid.include?(dep) } then
          # clear all references from the invalidated owner
          obj.class.domain_attributes.each_metadata { |attr_md| obj.clear_attribute(attr_md.to_sym) }
          invalid << obj
          logger.debug { "Invalidated #{obj.qp} since it was created solely to hold subsequently invalidated dependents." }
          true
        end
      end
    end
    
    # Returns whether the given domain object satisfies at least one of the following conditions:
    # * it does not have an owner among the invalid objects
    # * it has an owner among the valid objects
    #
    # @param [Resource] obj the domain object to check
    # @param [<Resource>] valid the valid migrated objects
    # @param [<Resource>] invalid the invalid migrated objects
    # @return [Boolean] whether the owner is valid 
    def owner_valid?(obj, valid, invalid)
      otypes = obj.class.owners
      invalid.all? { |other| not otypes.include?(other.class) } or
        valid.any? { |other| otypes.include?(other.class) }
    end

    # @param [Migratable] obj the migrated object
    # @return [Boolean] whether the migration is successful
    def migration_valid?(obj)
      if obj.migration_valid? then
        true
      else
        logger.debug { "Migrated #{obj.qp} is invalid." }
        false
      end
    end

    # Creates an instance of the given klass from the given row.
    # The new klass instance and all intermediate migrated instances are added to the
    # created set.
    #
    # @param [Class] klass
    # @param [{Symbol => Object}] row the input row
    # @param [<Resource>] created the migrated instances for this row
    # @return [Resource] the new instance
    def create(klass, row, created)
      # the new object
      logger.debug { "Migrator building #{klass.qp}..." }
      created << obj = klass.new
      migrate_attributes(obj, row, created)
      add_defaults(obj, row, created)
      logger.debug { "Migrator built #{obj}." }
      obj
    end
    
    # @param [Resource] the migration object
    # @param row (see #create)
    # @param [<Resource>] created (see #create)
    def migrate_attributes(obj, row, created)
      # for each input header which maps to a migratable target attribute metadata path,
      # set the target attribute, creating intermediate objects as needed.
      @cls_paths_hash[obj.class].each do |path|
        header = @header_map[path][obj.class]
        # the input value
        value = row[header]
        next if value.nil?
        # fill the reference path
        ref = fill_path(obj, path[0...-1], row, created)
        # set the attribute
        migrate_attribute(ref, path.last, value, row)
      end
    end
    
    # @param [Resource] the migration object
    # @param row (see #create)
    # @param [<Resource>] created (see #create)
    def add_defaults(obj, row, created)
      dh = @def_hash[obj.class] || return
      dh.each do |path, value|
        # fill the reference path
        ref = fill_path(obj, path[0...-1], row, created)
        # set the attribute to the default value unless there is already a value
        ref.merge_attribute(path.last.to_sym, value)
      end
    end

    # Fills the given reference Attribute path starting at obj.
    #
    # @param row (see #create)
    # @param created (see #create)
    # @return the last domain object in the path
    def fill_path(obj, path, row, created)
      # create the intermediate objects as needed (or return obj if path is empty)
      path.inject(obj) do |parent, attr_md|
        # the referenced object
        parent.send(attr_md.reader) or create_reference(parent, attr_md, row, created)
      end
    end

    # Sets the given migrated object's reference attribute to a new referenced domain object.
    #
    # @param [Resource] obj the domain object being migrated
    # @param [Attribute] attr_md the attribute being migrated
    # @param row (see #create)
    # @param created (see #create)
    # @return the new object
    def create_reference(obj, attr_md, row, created)
      if attr_md.type.abstract? then
        raise MigrationError.new("Cannot create #{obj.qp} #{attr_md} with abstract type #{attr_md.type}")
      end
      ref = attr_md.type.new
      ref.migrate(row, Array::EMPTY_ARRAY)
      obj.send(attr_md.writer, ref)
      created << ref
      logger.debug { "Migrator created #{obj.qp} #{attr_md} #{ref}." }
      ref
    end

    # Sets the given attribute value to the filtered input value. If there is a filter
    # defined for the attribute, then that filter is applied. If there is a migration
    # shim method with name +migrate_+_attribute_, then than method is called on the
    # (possibly filtered) value. The target object attribute is set to the resulting
    # filtered value. 
    #
    # @param [Migratable] obj the target domain object
    # @param [Attribute] attr_md the target attribute
    # @param value the input value
    # @param [{Symbol => Object}] row the input row
    def migrate_attribute(obj, attr_md, value, row)
      # if there is a shim migrate_<attribute> method, then call it on the input value
      value = filter_value(obj, attr_md, value, row) || return
      # set the attribute
      begin
        obj.send(attr_md.writer, value)
      rescue Exception
        raise MigrationError.new("Could not set #{obj.qp} #{attr_md} to #{value.qp} - #{$!}")
      end
      logger.debug { "Migrated #{obj.qp} #{attr_md} to #{value}." }
    end
    
    # Calls the shim migrate_<attribute> method or config filter on the input value.
    #
    # @param value the input value
    # @return the input value, if there is no filter, otherwise the filtered value
    def filter_value(obj, attr_md, value, row)
      filter = filter_for(obj, attr_md)
      return value if filter.nil?
      fval = filter.call(obj, value, row)
      unless value == fval then
        logger.debug { "Migration filter transformed #{obj.qp} #{attr_md} value from #{value.qp} to #{fval.qp}." }
      end
      fval
    end
    
    def filter_for(obj, attr_md)
      flts = @attr_flt_hash[obj.class] || return
      flts[attr_md]
    end

    # @param [Resource] obj the domain object to save in the database
    # @return [Resource, nil] obj if the save is successful, nil otherwise
    def save(obj, database)
      if @create then
        if database.find(obj) then
          logger.debug { "Migrator ignored record #{current_record}, since it already exists as #{obj.printable_content(obj.class.secondary_key_attributes)} with id #{obj.identifier}." }
        else
          logger.debug { "Migrator creating #{obj}..." }
          database.create(obj)
          logger.debug { "Migrator creating #{obj}." }
        end
      else
        logger.debug { "Migrator saving #{obj}..." }
        database.save(obj)
        logger.debug { "Migrator saved #{obj}." }
      end
    end
    
    def current_record
      @rec_cnt + 1
    end

    # @param [<String>, String] files the migration fields mapping file or file array
    # @return [{Class => {Attribute => Symbol}}] the class => path => header hash
    #   loaded from the mapping files
    def load_field_map_files(files)
      map = LazyHash.new { Hash.new }
      files.enumerate { |file| load_field_map_file(file, map) }

      # include the target class
      map[@target_class] ||= Hash.new
      # include the default classes
      @def_hash.each_key { |klass| map[klass] ||= Hash.new }

      # add superclass paths into subclass paths
      map.each do |klass, path_hdr_hash|
        map.each do |other, other_path_hdr_hash|
          if klass < other then
            # add, but don't replace, path => header entries from superclass
            path_hdr_hash.merge!(other_path_hdr_hash) { |key, old, new| old }
          end
        end
      end

      # include only concrete classes
      classes = map.keys
      map.delete_if do |klass, paths|
        klass.abstract? or classes.any? { |other| other < klass }
      end

      map
    end
    
    # @param [String] file the migration fields configuration file
    # @param [{Class => {Attribute => Symbol}}] hash the class => path => header hash
    #   loaded from the configuration file
    def load_field_map_file(file, hash)
      # load the field mapping config file
      begin
        config = YAML::load_file(file)
      rescue
        raise MigrationError.new("Could not read field map file #{file}: " + $!)
      end

      # collect the class => path => header entries
      config.each do |field, attr_list|
        next if attr_list.blank?
        # the header accessor method for the field
        header = @loader.accessor(field)
        raise MigrationError.new("Field defined in migration configuration #{file} not found in input file #{@input} headers: #{field}") if header.nil?
        # associate each attribute path in the property value with the header
        attr_list.split(/,\s*/).each do |path_s|
          klass, path = create_attribute_path(path_s)
          hash[klass][path] = header
        end
      end
    end
    
    # Loads the defaults config files.
    #
    # @param [<String>, String] files the file or file array to load
    # @return [<Class => <String => Object>>] the class => path => default value entries 
    def load_defaults_files(files)
      # collect the class => path => value entries from each defaults file
      hash = LazyHash.new { Hash.new }
      files.enumerate { |file| load_defaults_file(file, hash) }
      hash
    end
    
    # Loads the defaults config file into the given hash.
    #
    # @param [String] file the file to load
    # @param [<Class => <String => Object>>] hash the class => path => default value entries 
    def load_defaults_file(file, hash)
      begin
        config = YAML::load_file(file)
      rescue
        raise MigrationError.new("Could not read defaults file #{file}: " + $!)
      end
      # collect the class => path => value entries
      config.each do |path_s, value|
        next if value.nil_or_empty?
        klass, path = create_attribute_path(path_s)
        hash[klass][path] = value
      end
    end    
    # Loads the filter config files.
    #
    # @param [<String>, String] files the file or file array to load
    # @return [<Class => <String => Object>>] the class => path => default value entries 
    def load_filter_files(files)
      # collect the class => path => value entries from each defaults file
      hash = {}
      files.enumerate { |file| load_filter_file(file, hash) }
      hash
    end
    
    # Loads the filter config file into the given hash.
    #
    # @param [String] file the file to load
    # @param [<Class => <String => <Object => Object>>>] hash the class => path => input value => caTissue value entries 
    def load_filter_file(file, hash)
      begin
        config = YAML::load_file(file)
      rescue
        raise MigrationError.new("Could not read filter file #{file}: " + $!)
      end
      # collect the class => attribute => filter entries
      config.each do |path_s, flt|
        next if flt.nil_or_empty?
        klass, path = create_attribute_path(path_s)
        unless path.size == 1 then
          raise MigrationError.new("Migration filter configuration path not supported: #{path_s}")
        end
        attr = klass.standard_attribute(path.first.to_sym)
        flt_hash = hash[klass] ||= {}
        flt_hash[attr] = flt
      end
    end

    # @param [String] path_s a period-delimited path string path_s in the form _class_(._attribute_)+
    # @return [<Attribute>] the corresponding attribute metadata path
    # @raise [MigrationError] if the path string is malformed or an attribute is not found
    def create_attribute_path(path_s)
      names = path_s.split('.')
      # if the path starts with a capitalized class name, then resolve the class.
      # otherwise, the target class is the start of the path.
      klass = names.first =~ /^[A-Z]/ ? class_for_name(names.shift) : @target_class
      # there must be at least one attribute
      if names.empty? then
        raise MigrationError.new("Attribute entry in migration configuration is not in <class>.<attribute> format: #{value}")
      end
      # build the Attribute path
      path = []
      names.inject(klass) do |parent, name|
        attr = name.to_sym
        attr_md = begin
          parent.attribute_metadata(attr)
        rescue NameError
          raise MigrationError.new("Migration field mapping attribute #{parent.qp}.#{attr} not found: #{$!}")
        end
        if attr_md.collection? then
          raise MigrationError.new("Migration field mapping attribute #{parent.qp}.#{attr} is a collection, which is not supported")
        end
        path << attr_md
        attr_md.type
      end
      # return the starting class and Attribute path.
      # note that the starting class is not necessarily the first path attribute declarer, since the
      # starting class could be the concrete target class rather than an abstract declarer. this is
      # important, since the class must be instantiated.
      [klass, path]
    end
    
    # @param [String] name the class name, without the {#context_module}
    # @return [Class] the corresponding class
    def class_for_name(name)
      # navigate through the scope to the final class
      name.split('::').inject(context_module) do |ctxt, cnm|
        ctxt.const_get(cnm)
      end
    end
    
    # The context module is given by the target class {ResourceClass#domain_module}.
    #
    # @return [Module] the class name resolution context
    def context_module
      @target_class.domain_module
    end

    # @return a new class => [paths] hash from the migration fields configuration map
    def create_class_paths_hash(fld_map, def_map)
      hash = {}
      fld_map.each { |klass, path_hdr_hash| hash[klass] = path_hdr_hash.keys.to_set }
      def_map.each { |klass, path_val_hash| (hash[klass] ||= Set.new).merge(path_val_hash.keys) }
      hash
    end

    # @return a new path => class => header hash from the migration fields configuration map
    def create_header_map(fld_map)
      hash = LazyHash.new { Hash.new }
      fld_map.each do |klass, path_hdr_hash|
        path_hdr_hash.each { |path, hdr| hash[path][klass] = hdr }
      end
      hash
    end
  end
end