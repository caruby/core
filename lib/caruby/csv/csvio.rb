require 'rubygems'
gem 'fastercsv'

require 'fileutils'
require 'faster_csv'
require 'caruby/util/options'
require 'caruby/util/collection'

# CsvIO reads or writes CSV records.
# This class wraps a FasterCSV with the following modifications:
# * relax the date parser to allow dd/mm/yyyy dates
# * don't convert integer text with a leading zero to an octal number
# * allow one custom converter with different semantics: if the converter block
#   call returns nil, then continue conversion, otherwise return the converter
#   result. This differs from FasterCSV converter semantics which calls converters
#   as long the result ==  the input field value. The CsvIO converter semantics
#   supports converters that intend a String result to be the converted result.
#
# CsvIO is Enumerable, but does not implement the complete Ruby IO interface.
class CsvIO
  include Enumerable

  # Returns the CSV field access header symbols.
  attr_reader :headers

  # Opens the CSV file and calls the given block with this CsvIO as the argument.
  #
  # @see #initialize the supported options
  def self.open(file, options=nil) # :yields: csvio
    csvio = self.new(file, options)
    if block_given? then
      yield csvio
      csvio.close
    end
  end

  # #open the given CSV file and options, and call {#each} with the given block.
  def self.foreach(file, options=nil, &block) # :yields: record
    self.open(file, options=nil) { |csvio| csvio.each(&block) }
  end

  # Creates a new CsvIO for the specified source file.
  # If a converter block is given, then it is added to the CSV converters list.
  def initialize(file, options=nil, &converter)
    # the CSV file open mode
    mode = Options.get(:mode, options, "r")
    # the CSV headers option; can be boolean or array
    hdr_opt = Options.get(:headers, options)
    # there is a header record by default for an input CSV file
    hdr_opt ||= true if mode =~ /^r/
    # make parent directories if necessary for an output CSV file
    File.makedirs(File.dirname(file)) if mode =~ /^w/
    # if headers aren't given, then convert the input CSV header record names to underscore symbols
    hdr_cvtr = :symbol unless Enumerable === hdr_opt
     # make a custom converter
    custom = Proc.new { |f, info| convert(f, info, &converter) }
    # open the CSV file
    @csv = FasterCSV.open(file, mode, :headers => hdr_opt, :header_converters => hdr_cvtr, :return_headers => true, :write_headers => true, :converters => custom)
    # the header => field name hash:
    # if the header option is set to true, then read the input header line.
    # otherwise, parse an empty string which mimics an input header line.
    hdr_row = case hdr_opt
    when true then
      @csv.shift
    when Enumerable then
      ''.parse_csv(:headers => hdr_opt, :header_converters => :symbol, :return_headers => true)
    else
      raise ArgumentError.new("CSV headers option value not supported: #{hdr_opt}")
    end
    # the header row headers
    @headers = hdr_row.headers
    # the header name => symbol map
    @hdr_sym_hash = hdr_row.to_hash.invert
  end

  # Closes the CSV file and trash file if necessary.
  def close
    @csv.close
    @trash.close if @trash
  end

  # Returns the header accessor method for the given input header name.
  def accessor(header)
    @hdr_sym_hash[header]
  end

  # Sets the trash output file. This creates a separate CSV output file distinct from the input CSV file.
  # This is useful for writing rejected rows from the input. The output file has a header row.
  def trash=(file)
    @trash = FasterCSV.open(file, 'w', :headers => true, :header_converters => :symbol, :write_headers => true)
  end

  # Writes the row to the trash file if the trash file is set.
  #
  #@param [{Symbol => Object}] row the rejected input row
  def reject(row)
    @trash << row if @trash
  end

  # Iterates over each CSV row, yielding a row for each iteration.
  # This method closes the CSV file after the iteration completes.
  def each
    begin
      # parse each line
      @csv.each { |row| yield row }
    ensure
      close
    end
  end

  # @return the next CSV row
  # @see #each
  def read
    @csv.shift
  end

  alias :shift :read

  # Writes the given row to the CSV file.
  #
  #@param [{Symbol => Object}] row the input row
  def write(row)
    @csv << row
  end

  alias :<< :write

  private

  # 3-letter months => month sequence hash.
  MMM_MM_MAP = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'].to_compact_hash_with_index do |mmm, index|
    index < 9 ? ('0' + index.succ.to_s) : index.succ.to_s
  end

  # DateMatcher relaxes the FasterCSV DateMatcher to allow dd/mm/yyyy dates.
  DateMatcher = / \A(?: (\w+,?\s+)?\w+\s+\d{1,2},?\s+\d{2,4} | \d{1,2}-\w{3}-\d{2,4} | \d{4}[-\/]\d{1,2}[-\/]\d{1,2} | \d{1,2}[-\/]\d{1,2}[-\/]\d{2,4} )\z /x

  # @param f the input field value to convert
  # @param info the CSV field info
  # @return the converted value
  def convert(f, info)
    return if f.nil?
    # the block has precedence
    value = yield(f, info) if block_given?
    # integer conversion
    value ||= Integer(f) if f =~ /^[1-9]\d*$/
    # date conversion
    value ||= convert_date(f) if f =~ CsvIO::DateMatcher
    # float conversion
    value ||= (Float(f) rescue f) if f =~ /^\d+\.\d*$/ or f =~ /^\d*\.\d+$/
    # return converted value or the input field if there was no conversion
    value || f
  end

  # @param [String] the input field value
  # @return [Date] the converted date
  def convert_date(f)
    # If input value is in dd-mmm-yy format, then reformat.
    # Otherwise, parse as a Date if possible.
    if f =~ /^\d{1,2}-\w{3}-\d{2,4}$/ then
      ddmmyy = reformat_dd_mmm_yy_date(f) || return
      convert_date(ddmmyy)
#    elsif f =~ /^\w{3} \d{1,2}, \d{4}$/ then
#      ddmmyy = reformat_mmm_dd_yyyy_date(f) || return
#      convert_date(ddmmyy)
    else
      Date.parse(f, true) rescue nil
    end
  end

  # @param [String] the input field value in dd-mmm-yy format
  # @return [String] the reformatted date String in mm/dd/yy format
  def reformat_dd_mmm_yy_date(f)
    all, dd, mmm, yy = /^(\d{1,2})-([[:alpha:]]{3})-(\d{2,4})$/.match(f).to_a
    mm = MMM_MM_MAP[mmm.downcase] || return
    "#{mm}/#{dd}/#{yy}"
  end
#  # @param [String] the input field value in 'mmmd d, yyyy' format
#  # @return [String] the reformatted date String in mm/dd/yyyy format
#  def reformat_mmm_dd_yyyy_date(f)
#    all, mmm, dd, yyyy = /^(\w{3}) (\d{1,2}), (\d{4})$/.match(f).to_a
#    mm = MMM_MM_MAP[mmm.downcase] || return
#    "#{mm}/#{dd}/#{yyyy}"
#  end
end
