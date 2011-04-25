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
    # @option opts [String] :database required application {CaRuby::Database}
    # @option opts [String] :target required target domain class
    # @option opts [String] :mapping required input field => caTissue attribute mapping file
    # @option opts [String] :defaults optional caTissue attribute => value default mapping file
    # @option opts [String] :input required source file to migrate
    # @option opts [String] :shims optional array of shim files to load
    # @option opts [String] :unique ensures that migrated objects which include the {Resource::Unique}
    # @option opts [String] :create optional flag indicating that existing target objects are ignored
    # @option opts [String] :bad optional invalid record file
    # @option opts [Integer] :offset zero-based starting source record number to process (default 0)
    # @option opts [Boolean] :quiet suppress output messages
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

    UNIQUIFY_SHIM = File.join(File.dirname(__FILE__), 'uniquify.rb')

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
      logger.debug { "Migrator options: #{opts.qp}" }
      @fld_map_file = opts[:mapping]
      raise MigrationError.new("Migrator missing required field mapping file parameter") if @fld_map_file.nil?
      @def_file = opts[:defaults]
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
      @print_progress = !opts[:quiet]
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
      logger.info { "Migration input file: #{@input}." }
      @loader = CsvIO.new(@input) do |value, info|
        value unless @nonstring_headers.include?(info.header)
      end

      # create the class => path => header hash
      fld_map = load_field_map(@fld_map_file)
      # create the class => path => default value hash
      @def_hash = @def_file ? load_defaults(@def_file) : LazyHash.new { Hash.new }
      # create the class => paths hash
      @cls_paths_hash = create_class_paths_hash(fld_map, @def_hash)
      # create the path => class => header hash
      @header_map = create_header_map(fld_map)
      # add missing owner classes (copy the keys rather than using each_key since the hash is updated)
      @cls_paths_hash.keys.each { |klass| add_owners(klass) }
      # order the creatable classes by dependency, owners first, to smooth the migration process
      @creatable_classes = @cls_paths_hash.keys.sort! { |klass, other| other.depends_on?(klass) ? -1 : (klass.depends_on?(other) ? 1 : 0) }
      # print the maps
      print_hash = LazyHash.new { Hash.new }
      @cls_paths_hash.each do |klass, paths|
        print_hash[klass.qp] = paths.map { |path| {path.map { |attr_md| attr_md.to_sym  }.join('.') => @header_map[path][klass] } }
      end
      logger.info { "Migration paths:\n#{print_hash.pp_s}" }
      logger.info { "Migration creatable classes: #{@creatable_classes.qp}." }
      unless @def_hash.empty? then logger.info { "Migration defaults: #{@def_hash.qp}." } end
      
      # add shim modifiers
      load_shims(@shims)
      
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

    # Adds missing klass owner classes to the migration class path hash (with empty paths).
    def add_owners(klass)
      klass.owners.each do |owner|
        next if @cls_paths_hash.detect_key { |other| other <= owner } or owner.abstract?
        logger.debug { "Migrator adding #{klass.qp} owner #{owner.qp}" }
        @cls_paths_hash[owner] = Array::EMPTY_ARRAY
        add_owners(owner)
      end
    end

    # Creates the class => +migrate_+_<attribute>_ hash for the given klasses.
    def create_migration_method_hashes
      # the attribute metadata => migration method hash variable
      @attr_md_mgt_mth_map = {}
      # the class => attribute => migration method hash variable
      @mgt_mth_hash = {}
      # collect the migration methods
      customizable_class_attributes.each { |klass, attr_mds| add_migration_methods(klass, attr_mds) }
      # print the migration shim methods
      unless @mgt_mth_hash.empty? then
        printer_hash = LazyHash.new { Array.new }
        @mgt_mth_hash.each do |klass, attr_mth_hash|
          mthds = attr_mth_hash.values
          printer_hash[klass.qp] = mthds unless mthds.empty?
        end
        logger.info("Migration shim methods: #{printer_hash.pp_s}.")
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
    def add_migration_methods(klass, attr_mds)
      # the migrate methods, excluding the Migratable migrate_references method
      mths = klass.instance_methods(true).select { |mth| mth =~ /^migrate.(?!references)/ }
      return if mths.empty?

      # the attribute => migration method hash
      attr_mth_hash = {}
      mths.each do |mth|
        # the attribute suffix, e.g. name for migrate_name or Name for migrateName
        suffix = /^migrate(_)?(.*)/.match(mth).captures[1]
        # the attribute name
        attr_nm = suffix[0, 1].downcase + suffix[1..-1]
        # the attribute for the name, or skip if no such attribute
        attr = klass.standard_attribute(attr_nm) rescue next
        # associate the attribute => method
        attr_mth_hash[attr] = mth
      end

      # for each class path terminal attribute metadata, add the migration methods
      # to the attribute metadata => migration method hash
      attr_mds.each do |attr_md|
        # the attribute migration method
        mth = attr_mth_hash[attr_md.to_sym]
        # associate the AttributeMetadata => method
        @attr_md_mgt_mth_map[attr_md] ||= mth if mth
      end
      @mgt_mth_hash[klass] = attr_mth_hash
    end

    # loads the shim files.
    def load_shims(files)
      logger.debug { "Loading shims with load path #{$:.pp_s}..." }
      files.each do |file|
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
    # The required block to this method is described in {#migrate}.
    def migrate_rows # :yields: target
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
          # If there is a bad file then warn, reject and continue.
          # Otherwise, bail.
          if @bad_rec_file then
            logger.warn("Migration not performed on record #{rec_no}.")
            @loader.reject(row)
          else
            raise MigrationError.new("Migration not performed on record #{rec_no}")
          end
        end
        @rec_cnt += 1
      end
      logger.info("Migrated #{mgt_cnt} of #{@rec_cnt} records.")
    end
    
    # Prints a +\++ progress indicator to stdout.
    #
    # @param [Integer] count the progress step count
    def print_progress(count)
      if count % 72 == 0 then puts "+" else print "+" end
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
    def migrate_row(row) # :yields: target
      # create an instance for each creatable class
      created = Set.new
      migrated = @creatable_classes.map { |klass| create(klass, row, created) }
      # migrate each object from the input row
      created.each { |obj| obj.migrate(row, migrated) }
      # remove invalid migrations
      valid, invalid = migrated.partition { |obj| migration_valid?(obj) }
      # set the references
      valid.each { |obj| obj.migrate_references(row, migrated, @mgt_mth_hash[obj.class]) }
      # the target object
      target = valid.detect { |obj| @target_class === obj } || return
      # the target is invalid if it has an invalid owner
      return unless owner_valid?(target, valid, invalid)
      logger.debug { "Migrated target #{target}." }
      target
    end
    
    # Returns whether the given domain object satisfies at least one of the following conditions:
    # * it has an owner among the valid objects
    # * it does not have an owner among the invalid objects
    #
    # @param [Resource] obj the domain object to check
    # @param [<Resource>] valid the valid migrated objects
    # @param [<Resource>] invalid the invalid migrated objects
    # @return [Boolean] whether the domain object is valid 
    def owner_valid?(obj, valid, invalid)
      otypes = obj.class.owners
      invalid.all? { |other| not otypes.include?(other.class) } or
        valid.any? { |other| otypes.include?(other.class) }
    end

    # @param [Migratable] obj the migrated object
    # @return whether the migration is successful
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
      created << obj = klass.new
      migrate_attributes(obj, row, created)
      add_defaults(obj, row, created)
      logger.debug { "Migrator created #{obj}." }
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
      @def_hash[obj.class].each do |path, value|
        # fill the reference path
        ref = fill_path(obj, path[0...-1], row, created)
        # set the attribute to the default value unless there is already a value
        ref.merge_attribute(path.last.to_sym, value)
      end
    end

    # Fills the given reference AttributeMetadata path starting at obj.
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
    # @param [AttributeMetadata] attr_md the attribute being migrated
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

    # Sets the obj migratable AttributeMetadata attr_md to value from the given input row.
    def migrate_attribute(obj, attr_md, value, row)
      # a single value can be used for both a Numeric and a String attribute; coerce the value if necessary
      # if there is a shim migrate_<attribute> method, then call it on the input value
      mth = @attr_md_mgt_mth_map[attr_md]
      if mth and obj.respond_to?(mth) then
        value = obj.send(mth, value, row)
        return if value.nil?
      end
      # set the attribute
      begin
        obj.send(attr_md.writer, value)
      rescue Exception => e
        raise MigrationError.new("Could not set #{obj.qp} #{attr_md} to #{value.qp} - #{e}")
      end
      logger.debug { "Migrated #{obj.qp} #{attr_md} to #{value}." }
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

    # @param [String] file the migration fields configuration file
    # @return [{Class => {AttributeMetadata => Symbol}}] the class => path => header hash
    #   loaded from the configuration file
    def load_field_map(file)
      # load the field mapping config file
      begin
        config = YAML::load_file(file)
      rescue
        raise MigrationError.new("Could not read field map file #{file}: " + $!)
      end

      # collect the class => path => header entries
      map = LazyHash.new { Hash.new }
      config.each do |field, attr_list|
        next if attr_list.blank?
        # the header accessor method for the field
        header = @loader.accessor(field)
        raise MigrationError.new("Field defined in migration configuration #{file} not found in input file #{@input} headers: #{field}") if header.nil?
        attr_list.split(/,\s*/).each do |path_s|
          klass, path = create_attribute_path(path_s)
          map[klass][path] = header
        end
      end

      # include the target class
      map[@target_class] ||= Hash.new

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
      classes = map.enum_keys
      map.delete_if do |klass, paths|
        klass.abstract? or classes.any? { |other| other < klass }
      end
      map
    end
    
    def load_defaults(file)
      # load the field mapping config file
      begin
        config = YAML::load_file(file)
      rescue
        raise MigrationError.new("Could not read defaults file #{file}: " + $!)
      end

      # collect the class => path => value entries
      map = LazyHash.new { Hash.new }
      config.each do |path_s, value|
        next if value.nil_or_empty?
        klass, path = create_attribute_path(path_s)
        map[klass][path] = value
      end

      map
    end

    # @param [String] path_s a period-delimited path string path_s in the form _class_(._attribute_)+
    # @return [<AttributeMetadata>] the corresponding attribute metadata path
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
      # build the AttributeMetadata path
      path = []
      names.inject(klass) do |parent, name|
        attr = name.to_sym
        attr_md = begin
          parent.attribute_metadata(attr)
        rescue NameError
          raise MigrationError.new("Migration field mapping attribute #{parent.qp}.#{attr} not found: #{$!}")
        end
        path << attr_md
        attr_md.type
      end
      # return the starting class and AttributeMetadata path.
      # note that the starting class is not necessarily the first path attribute declarer, since the
      # starting class could be the concrete target class rather than an abstract declarer. this is
      # important, since the class must be instantiated.
      [klass, path]
    end
    
    def class_for_name(name)
      # navigate through the scope to the final class
      name.split('::').inject(@target_class.domain_module) do |scope, cnm|
        scope.const_get(cnm)
      end
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