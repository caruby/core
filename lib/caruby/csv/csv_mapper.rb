require 'caruby/csv/csvio'
require 'caruby/util/properties'

module CaRuby
  # Maps a CSV extract to a caBIG application.
  #
  # _Note_: CsvMapper is an experimental class used only by the CaTissue::Extractor.
  class CsvMapper
    attr_reader :csvio, :classes

    # Creates a new CsvMapper from the following parameters:
    # * the required mapping configuration file config
    # * the required target class
    # * the required CSV file name
    # * additional CsvIO options as desired
    #
    # If the converter block is given to this method, then that block is called to convert
    # source CSV field values as described in the FasterCSV.
    def initialize(config, target, csv, options={}, &converter) # :yields: value, info
      @target = target
      # load the config
      fld_path_hash = load_config(config)
      # the default input fields are obtained by CsvIO from the first line of the input;
      # the default output fields are the field mapping config keys in order
      options[:headers] ||= config_headers(config) if options[:mode] =~ /^w/
      # the CSV wrapper; do this before making the header map since the CsvIO-generated headers
      # are used to build the header map
      @csvio = CsvIO.new(csv, options) do |value, info|
        # nonstring headers are determined later in this initializer
        if value and @string_headers.include?(info.header) then
          value
        elsif block_given? then
          # call custom converter first, if any
          yield(value, info)
        end
      end
      # the class => paths hash; populated in map_headers
      @cls_paths_hash = LazyHash.new { Set.new }
      # the path => header hash; do this after making the CsvIO
      @cls_paths_hash, @hdr_map = map_headers(fld_path_hash)
      # the top-level classes
      klasses = @cls_paths_hash.keys
      # include the target class
      @cls_paths_hash[@target] ||= Set.new
      # add superclass paths into subclass paths
      @cls_paths_hash.each do |klass, paths|
        @cls_paths_hash.each { |other, other_paths| paths.merge!(other_paths) if klass < other }
      end
      # include only concrete classes
      @classes = @cls_paths_hash.keys
      @cls_paths_hash.delete_if do |klass, paths|
        klass.abstract? or klasses.any? { |other| other < klass }
      end
      # Collect the non-string input fields for the custom CSV converter.
      @string_headers = Set.new
      @hdr_map.each do |path, cls_hdr_hash|
        last = path.last
        @string_headers.merge!(cls_hdr_hash.values) if Domain::Attribute === last and last.type == String
      end
    end

    # Returns the given klass's mapped Attribute paths.
    # The default klass is the target class.
    def paths(klass=nil)
      klass ||= @target
      @cls_paths_hash[klass]
    end

    # Returns the header mapped by the given Attribute path and starting klass.
    # The default klass is the target class.
    def header(path, klass=nil)
      klass ||= @target
      @hdr_map[path][klass]
    end

    private

    # Returns the field => path list hash from the field mapping configuration file.
    def load_config(file)
      begin
        config = YAML::load_file(file)
      rescue
        raise ConfigurationError.new("Could not read field mapping configuration file #{file}: " + $!)
      end
    end

    def config_headers(config)
      File.open(config) do |file|
        file.map { |line| line[/(^.+):/, 1] }.compact
      end
    end

    # @param [{Symbol => <Attribute>}] config the field => path list configuration
    # @return [({Symbol => <Attribute>}, {Class => {<Attribute> => Symbol>}})]
    #   the class => paths hash and the path => class => header hash
    def map_headers(config)
      # the class => paths hash; populated in map_headers
      cls_paths_hash = LazyHash.new { Set.new }
      hdr_map = LazyHash.new { Hash.new }
      config.each do |field, attr_list|
        next if attr_list.blank?
        # the header accessor method for the field
        header = @csvio.accessor(field)
        raise ConfigurationError.new("Field defined in field mapping configuration not found: #{field}") if header.nil?
        attr_list.split(/,\s*/).each do |path_s|
          klass, path = create_attribute_path(path_s)
          hdr_map[path][klass] = header
          # associate the class with the path
          cls_paths_hash[klass] << path
        end
      end
      [cls_paths_hash, hdr_map]
    end

    # Returns an array of Attribute or symbol objects for the period-delimited path string path_s in the
    # pattern (_class_|_attribute_)(+.+_attribute_)*, e.g.:
    #   ClinicalStudy.status
    #   study.status
    # The default starting class is this CvsMapper's target class.
    # Raises ConfigurationError if the path string is malformed or an attribute is not found.
    def create_attribute_path(path_s)
      names = path_s.split('.')
      # if the path starts with a capitalized class name, then resolve the class.
      # otherwise, the target class is the start of the path.
      klass = names.first =~ /^[A-Z]/ ? @target.domain_module.const_get(names.shift) : @target
      # there must be at least one attribute
      if names.empty? then
        raise ConfigurationError.new("Attribute entry in CSV field mapping is not in <class>.<attribute> format: #{value}")
      end
      # build the Attribute path by traversing the names path
      # if the name corresponds to a parent attribute, then add the attribute metadata.
      # otherwise, if the name is a method, then add the method.
      path = []
      names.inject(klass) do |parent, name|
        attr_md = parent.class.attribute_metadata(name) rescue nil
        if attr_md then
          # name is an attribute: add the attribute metadata and navigate to the attribute domain type
          path << attr_md
          attr_md.type
        elsif parent.method_defined?(name) then
          # name is not a pre-defined attribute but is a method: add the method symbol to the path and halt traversal
          path << name.to_sym
          break
        else
          # method not defined
          raise ConfigurationError.new("CSV field mapping attribute not found: #{parent.qp}.#{name}")
        end
      end
      # add remaining non-attribute symbols
      tail = names[path.size..-1].map { |name| name.to_sym }
      path.concat(tail)
      # return the starting class and path
      # Note that the starting class is not necessarily the first path Attribute declarer, since the
      # starting class could be a concrete subclass of an abstract declarer. this is important, since the class
      # must be instantiated.
      [klass, path]
    end
  end
end