require 'jinx/helpers/validation'

# Mix-in for standard Person attributes.
module CaRuby
  module Person
    class Name
      # @return [String] the salutation, e.g. 'Mr.'
      attr_accessor :salutation
      
      # @return [String] the trailing name qualifier, e.g. 'III'
      attr_accessor :qualifier
      
      # @return [String] the trailing name credentials, e.g. 'MD'
      attr_accessor :credentials
      
      # @return [String] the first name
      attr_reader :first
      
      # @return [String] the middle name
      attr_reader :middle
      
      # @return [String] the ;ast name
      attr_reader :last

      # Creates a new Name with the required last and optional first and middle components.
      #
      # @param [String] last the required last name
      # @param [String, nil] first the optional first name
      # @param [String, nil] middle the optional middle name
      def initialize(last, first=nil, middle=nil)
        # replace empty with nil
        @first = first unless first == ''
        @last = last unless last == ''
        @middle = middle unless middle == ''
      end

      # @return [(String, String, String)] this Name as an array consisting of the first,
      # middle and last fields
      #
      # @example
      #  Person.parse("Abe Lincoln").to_a #=> ["Abe", nil, "Lincoln"]
      def to_a
        [@first, @middle, @last]
      end

      # @return [String] this Name in the format [Salutation] First [Middle] Last[, Credentials]
      def to_s
        name_s = [salutation, first, middle, last, qualifier].reject { |part| part.nil? }.join(' ')
        name_s << ', ' << credentials if credentials
        name_s
      end

      # @return [Boolean] whether this Person's first, middle and last name components equal the other Person's
      def ==(other)
        self.class == other.class and first == other.first and middle == other.middle and last == other.last
      end

      alias :inspect :to_s

      # Parses the name_s String into a Name. The name can be in one of the following formats:
      # * last, first middle
      # * [salutation] [first [middle]] last [qualifier] [, credentials]
      # where _salutation_ ends in a period.
      #
      # Example input:
      # * Longfellow, Henry Wadsworth
      # * Longfellow, Henry Gallifant Wadsworth
      # * Henry Longfellow
      # * Longfellow
      # * Mr. Henry Wadsworth Longfellow III, MD, Ph.D.
      #
      # @param [String] name_s the name to parse
      # @return [Name] the parsed Name
      def self.parse(name_s)
        return if name_s.blank?
        # the name component variables
        first = middle = last = salutation = qualifier = credentials = nil
        # split into comma-delimited tokens
        tokens = name_s.split(',')
        # the word(s) before the first comma
        before_comma = tokens[0].split(' ')
        # if this is a last, first middle format, then parse it that way.
        # otherwise the format is [salutation] [first [middle]] last [qualifier] [credentials]
        if before_comma.size == 1 then
          last = before_comma[0]
          if tokens.size > 1 then
            after_comma = tokens[1].split(' ')
            first = after_comma.shift
            middle = after_comma.join(' ')
          end
        else
          # extract the salutation from the front, if any
          salutation = before_comma.shift if salutation?(before_comma[0])
          # extract the qualifier from the end, if any
          qualifier = before_comma.pop if qualifier?(before_comma[-1])
          # extract the last name from the end
          last = before_comma.pop
          # extract the first name from the front
          first = before_comma.shift
          # the middle name is whatever is left before the comma
          middle = before_comma.join(' ')
          # the credentials are the comma-delimited words after the first comma
          credentials = tokens[1..-1].join(',').strip
        end
        # if there is only one name field, then it is the last name
        if last.nil? then
          last = first
          first = nil
        end
        # make the name
        name = self.new(last, first, middle)
        name.salutation = salutation
        name.qualifier = qualifier
        name.credentials = credentials
        name
      end

      # @raise [ValidationError] if there is neither a first nor a last name
      # or if there is a middle name but no first name
      def validate
        if last.nil? and first.nil? then
          raise Jinx::ValidationError.new("Name is missing both the first and last fields")
        end
        if !middle.nil? and first.nil? then
          raise Jinx::ValidationError.new("Name with middle field #{middle} is missing the first field")
        end
      end

      # @param [String] s a name fragment
      # @return [Boolean] whether the fragment ends in a period
      def self.salutation?(s)
        s =~ /\.$/
      end

      # Returns whether the given name fragment is a recognized qualifier. The following
      # qualifiers are recognized:
      # * +Jr+ with optional period
      # * +Sr+ with optional period
      # * +I+, +II+ or +III+
      #
      # @param [String] s a name fragment
      # @return [Boolean] whether s is a recognized qualifier
      def self.qualifier?(s)
        s and (s =~ /[J|S]r[.]?/ or s =~ /\AI+\Z/)
      end
    end
  end
end
