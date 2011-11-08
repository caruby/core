module CaRuby
  # Helper class which adds files to the Java class path.
  class ClassPathModifier
    # Adds the directories in the given path and all Java jar files contained in the directories
    # to the Java classpath.
    #
    # @param [String] path the colon or semi-colon separated directories
    def expand_to_class_path(path)
      # the path separator
      sep = path[WINDOWS_PATH_SEP] ? WINDOWS_PATH_SEP : UNIX_PATH_SEP
      # the path directories
      dirs = path.split(sep).map { |dir| File.expand_path(dir) }
      expanded = expand_jars(dirs)
      expanded.each { |dir| add_to_classpath(dir) }
    end

    private
  
    # The Windows semi-colon path separator.
    WINDOWS_PATH_SEP = ';'
  
    # The Unix colon path separator.
    UNIX_PATH_SEP = ':'
    
    # Expands the given directories to include the contained jar files.
    # If a directory contains jar files, then the jar files are included in
    # the resulting array. Otherwise, the directory itself is included in
    # the resulting array.
    #
    # @param [<String>] directories the directories containing jars to add
    # @return [<String>] each directory or its jars
    def expand_jars(directories)
      expanded = directories.map do |dir|
        jars = Dir[File.join(dir , "**", "*.jar")]
        jars.empty? ? [dir] : jars
      end
      expanded.flatten
    end

    # Adds the given jar file or directory to the classpath.
    #
    # @param [String] file the jar file or directory to add
    def add_to_classpath(file)
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
        # Append the file to the classpath.
        $CLASSPATH << file
      end
    end
  end
end  