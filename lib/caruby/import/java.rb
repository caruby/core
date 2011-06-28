#
# Include file to set up the classpath and logger.
#

# The jRuby Java bridge
require 'java'
require 'ftools'
require 'date'

require 'caruby/util/class'
require 'caruby/util/log'
require 'caruby/util/inflector'
require 'caruby/util/collection'

module Java
  private
  
  # The Windows semi-colon path separator.
  WINDOWS_PATH_SEP = ';'
  
  # The Unix colon path separator.
  UNIX_PATH_SEP = ':'
  
  public
  
  # Adds the directories in the given path and all Java jar files contained in the directories
  # to the execution classpath.
  #
  # @param [String] path the colon or semi-colon separated directories
  def self.add_path(path)
    # the path separator
    sep = path[WINDOWS_PATH_SEP] ? WINDOWS_PATH_SEP : UNIX_PATH_SEP
    # the path directories
    dirs = path.split(sep).map { |dir| File.expand_path(dir) }
    # Add all jars found anywhere within the directories to the the classpath.
    add_jars(*dirs)
    # Add the directories to the the classpath.
    dirs.each { |dir| add_to_classpath(dir) }
  end  
  
  # Adds the jars in the directories to the execution class path.
  #
  # @param [<String>] directories the directories containing jars to add
  def self.add_jars(*directories)
    directories.each do |dir|
      Dir[File.join(dir , "**", "*.jar")].each { |jar| add_to_classpath(jar) }
    end
  end
  
  # Adds the given jar file or directory to the classpath.
  #
  # @param [String] file the jar file or directory to add
  def self.add_to_classpath(file)
    unless File.exist?(file) then
      logger.warn("File to place on Java classpath does not exist: #{file}")
      return
    end
    if file =~ /.jar$/ then
      # require is preferred to classpath append for a jar file
      require file
    else
      # A directory must end in a slash since JRuby uses an URLClassLoader.
      if File.directory?(file) and not file =~ /\/$/ then file = file + '/' end
      $CLASSPATH << file
    end
  end

  module JavaUtil
    # Aliases Java Collection methods with the standard Ruby Set counterpart, e.g. +delete+ for +remove+.
    module Collection
      def to_a
        inject(Array.new) { |array, item| array << item }
      end

      # Removes the given item from this collection.
      def delete(item)
        # can't alias delete to remove, since a Java interface doesn't implement any methods
        remove(item)
      end

      # Removes the items from this collection for which the block given to this method returns a non-nil, non-false value.
      def delete_if
        removeAll(select { |item| yield item })
        self
      end
    end

    # Aliases Java List methods with the standard Ruby Array counterpart, e.g. +merge+ for +addAll+.
    module List
      # Returns whether this List has the same content as the other Java List or Ruby Array.
      def ==(other)
        Array === other ? to_a == other : equals(other)
      end

      # Removes the given item from this collection.
      def delete(item)
        remove(item)
      end
    end

    module Map
      # Returns whether this Set has the same content as the other Java Map or Ruby Hash.
      def ==(other)
        ::Hash === other ? (size == other.size and other.all? { |key, value| get(key) == value }) : equals(other)
      end

      # Merges the other Java Map or Ruby Hash into this Map. Returns this modified Map.
      #
      # If a block is given to this method, then the block determines the mapped value
      # as specified in the Ruby Hash merge method documentation.
      def merge(other)
        other.each do |key, value|
          value = yield(key, get(key), value) if block_given? and containsKey(key)
          put(key, value)
        end
        self
      end

      alias :merge! :merge
    end

    module Set
      # Returns whether this Set has the same content as the other Java Set or Ruby Set.
      def ==(other)
        ::Set === other ? (size == other.size and all? { |item| other.include?(item) }) : equals(other)
      end

      # Merges the other Enumerable into this Set. Returns this modified Set.
      #
      # This method conforms to the Ruby Set merge contract rather than the Ruby List and Hash
      # merge contract. Ruby Set merge modifies the Set in-place, whereas Ruby List and Hash
      # merge return a new collection.
      def merge(other)
        return self if other.nil?
        raise ArgumentError.new("Merge argument must be enumerable: #{other}") unless Enumerable === other
        other.each { |item| self << item }
        self
      end

      alias :merge! :merge
    end

    class HashSet
      alias :base__clear :clear
      private :base__clear
      def clear
        base__clear
        self
      end
    end

    class TreeSet
      alias :base__first :first
      private :base__first
      # Fixes the jRuby {TreeSet#first} to return nil on an empty set rather than raise a Java exception.
      def first
        empty? ? nil : base__first
      end
    end

    class ArrayList
      alias :base__clear :clear
      private :base__clear
      def clear
        base__clear
        self
      end
    end

    class Date
      # The millisecond-to-day conversion factor.
      MILLIS_PER_DAY = (60 * 60 * 1000) * 24

      # Converts this Java Date to a Ruby DateTime.
      #
      # @quirk caTissue Bug #165: API CPR create date validation is time zone dependent.
      #   Since Java Date accounts for DST and Ruby DateTime doesn't, this method makes the
      #   DST adjustment by subtracting a compensatory one-hour DST offset from the
      #   Java Date time zone offset and using that to set the DateTime offset.
      #   This ensures that Date conversion is idempotent, i.e.
      #     date.to_ruby_date().to_java_date == date
      #
      #   However, there can be adverse consequences for an application that assumes that the
      #   client time zone is the same as the server time zone, as described in caTissue
      #   Bug #165.
      #
      # @return [DateTime] the Ruby date
      def to_ruby_date
        calendar = java.util.Calendar.instance
        calendar.setTime(self)
        secs = calendar.timeInMillis.to_f / 1000
        # millis since epoch
        time = Time.at(secs)
        # convert UTC timezone millisecond offset to Rational fraction of a day
        offset_millis = calendar.timeZone.getOffset(calendar.timeInMillis).to_f
        if offset_millis.zero? then
          offset = 0
        else
          offset_days = offset_millis / MILLIS_PER_DAY
          offset_fraction = 1 / offset_days
          offset = Rational(1, offset_fraction)
        end
        # convert to DateTime
        DateTime.civil(time.year, time.mon, time.day, time.hour, time.min, time.sec, offset)
      end

      # Converts a Ruby Date or DateTime to a Java Date.
      #
      # @param [::Date, DateTime] date the Ruby date
      # @return [Date] the Java date
      def self.from_ruby_date(date)
        return if date.nil?
        # DateTime has time attributes, Date doesn't
        if DateTime === date then
          hour, min, sec = date.hour, date.min, date.sec
        else
          hour = min = sec = 0
        end
        # the Ruby time
        rtime = Time.local(sec, min, hour, date.day, date.mon, date.year, nil, nil, nil, nil)
        # millis since epoch
        millis = (rtime.to_f * 1000).truncate
        # the Java date factory
        calendar = java.util.Calendar.instance
        calendar.setTimeInMillis(millis)
        jtime = calendar.getTime
        # the daylight time flag
        isdt = calendar.timeZone.inDaylightTime(jtime)
        return jtime unless isdt
        # adjust the Ruby time for DST
        rtime = Time.local(sec, min, hour, date.day, date.mon, date.year, nil, nil, isdt, nil)
        millis = (rtime.to_f * 1000).truncate
        calendar.setTimeInMillis(millis)
        calendar.getTime
      end
    end
  end

  def self.now
    JavaUtil::Date.from_ruby_date(DateTime.now)
  end
  
  # @param [Class, String] the JRuby class or the full Java class name
  # @return (String, String] the package and base for the given name
  def self.split_class_name(name_or_class)
    name = Class === name_or_class ? name_or_class.java_class.name : name_or_class
    match = NAME_SPLITTER_REGEX.match(name)
    match ? match.captures : [nil, name]
  end
  
  private
  
  NAME_SPLITTER_REGEX = /^([\w.]+)\.(\w+)$/
end

class Class
  # Returns whether this is a Java wrapper class.
  def java_class?
    method_defined?(:java_class)
  end

  # Returns the Ruby class for the given class, as follows:
  # * If the given class is already a Ruby class, then return the class.
  # * If the class argument is a Java class or a Java class name, then
  #   the Ruby class is the JRuby wrapper for the Java class.
  #
  # @param [Class, String] the class or class name
  # @return [Class] the corresponding Ruby class
  def self.to_ruby(klass)
    case klass
      when Class then klass
      when String then Java.module_eval(klass)
      else to_ruby(klass.name)
    end
  end

  # @return [Boolean] whether this is a wrapper for an abstract Java class
  def abstract?
    java_class? and Java::JavaLangReflect::Modifier.isAbstract(java_class.modifiers)
  end

  # Returns whether the given PropertyDescriptor pd corresponds to a transient field in this class, or nil if there is no such field.
  def transient?(pd)
    begin
      field = java_class.declared_field(pd.name)
    rescue Exception
      # should occur only if a property is not a field; not an error
      return
    end
    Java::JavaLangReflect::Modifier.isTransient(field.modifiers) if field
  end

  # Returns this class's readable and writable Java PropertyDescriptors, or an empty Array if none.
  # If the hierarchy flag is set to +false+, then only this class's properties
  # will be introspected.
  def java_properties(hierarchy=true)
    return Array::EMPTY_ARRAY  unless java_class?
    info = hierarchy ? Java::JavaBeans::Introspector.getBeanInfo(java_class) : Java::JavaBeans::Introspector.getBeanInfo(java_class, java_class.superclass)
    info.propertyDescriptors.select { |pd| pd.write_method and property_read_method(pd) }
  end

  # Redefines the reserved method corresponeding to the given Java property descriptor pd
  # back to the Object implementation, if necessary.
  # If both this class and Object define a method with the property name,
  # then a new method is defined with the same body as the previous method.
  # Returns the new method symbol, or nil if name_or_symbol is not an occluded
  # Object instance method.
  #
  # This method undoes the jRuby clobbering of Object methods by Java property method
  # wrappers. The method is renamed as follows:
  # * +id+ is changed to :identifier
  # * +type+ is prefixed by the underscore subject class name, e.g. +Specimen.type => :specimen_type+,
  #   If the property name is +type+ and the subject class name ends in 'Type', then the attribute
  #   symbol is the underscore subject class name, e.g. +HistologicType.type => :histologic_type+.
  #
  # Raises ArgumentError if symbol is not an Object method.
  def unocclude_reserved_method(pd)
    oldname = pd.name.underscore
    return unless OBJ_INST_MTHDS.include?(oldname)
    oldsym = oldname.to_sym
    undeprecated = case oldsym
      when :id then :object_id
      when :type then :class
      else oldsym
    end
    rsvd_mth = Object.instance_method(undeprecated)
    base = self.qp.underscore
    newname = if oldname == 'id' then
      'identifier'
    elsif base[-oldname.length..-1] == oldname then
      base
    else
      "#{base}_#{oldname}"
    end
    newsym = newname.to_sym
    rdr = property_read_method(pd).name.to_sym
    alias_method(newsym, rdr)
    # alias the writers
    wtr = pd.write_method.name.to_sym
    alias_method("#{newsym}=".to_sym, wtr)
    # alias a camel-case Java-style method if necessary
    altname = newname.camelize
    unless altname == newname then
      alias_method(altname.to_sym, oldsym)
      alias_method("#{altname}=".to_sym, wtr)
    end
    # restore the old method to Object
    define_method(oldsym) { |*args| rsvd_mth.bind(self).call(*args) }
    newsym
  end

  # @quirk caCORE java.lang.Boolean is<name> is not introspected as a read method, since the type
  # must be primitive, i.e. `boolean is`<name>.
  #
  # @return [Symbol] the property descriptor pd introspected or discovered Java read Method
  def property_read_method(pd)
    return pd.read_method if pd.read_method
    return unless pd.get_property_type == Java::JavaLang::Boolean.java_class
    rdr = java_class.java_method("is#{pd.name.capitalize_first}") rescue nil
    logger.debug { "Discovered #{qp} #{pd.name} property non-introspected reader method #{rdr.name}." } if rdr
    rdr
  end
  
  private
  
  OBJ_INST_MTHDS = Object.instance_methods
end

class Array
  alias :equal__base :==
  # Overrides the standard == to compare a Java List with a Ruby Array.
  def ==(other)
    Java::JavaUtil::List === other ? other == self : equal__base(other)
  end
end
