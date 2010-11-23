require 'caruby/util/class'

class File
  [:gets, :readline, :readlines].each do |attr|
    # Overrides the standard method to infer a line separator from the input
    # if the separator argument is the default.
    redefine_method(attr) do |original|
      lambda do |*params|
        sep = params.first || default_line_separator
        send(original, sep)
      end
    end

    # Overrides the standard {#each} method to infer a line separator from the input
    # if the separator argument is not given.
    def each(separator=nil)
      while (line = gets(separator)) do
        yield line
      end
    end
  end

  private

  # Returns the default line separator. The logic is borrowed from the FasterCVS gem.
  def default_line_separator
    @def_line_sep ||= infer_line_separator
  end

  def infer_line_separator
    type_line_separator or content_line_separator or $/
  end

  def type_line_separator
    if [ARGF, STDIN, STDOUT, STDERR].include?(self) or
      (defined?(Zlib) and self.class == Zlib::GzipWriter) then
      return $/
    end
  end

  def content_line_separator
    begin
      saved_pos = pos  # remember where we were
      # read a chunk until a separator is discovered
      sep = discover_line_separator
      # tricky seek() clone to work around GzipReader's lack of seek()
      rewind
      # reset back to the remembered position
      chunks, residual = saved_pos.divmod(1024)
      chunks.times { read(1024) }
      read(residual)
    rescue IOError  # stream not opened for reading
    end
    sep
  end

  def discover_line_separator
    # read a chunk until a separator is discovered
    while (sample = read(1024)) do
      sample += read(1) if sample[-1, 1] == "\r" and not eof?
      # try to find a standard separator
      return $& if sample =~ /\r\n?|\n/
    end
  end
end