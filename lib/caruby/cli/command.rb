require 'optparse'
require 'caruby/cli/application'

module CaRuby
  module CLI
    # Command-line parsing errors.
    class CommandError < StandardError; end
      
    # Command-line parser and executor.
    class Command < Application
      # Command line application wrapper.
      # The specs parameter is an array of command line option and argument
      # specifications as follows:
      #
      # Each option specification is an array in the form:
      #   [option, short, long, class, description]
      # where:
      # * option is the option symbol, e.g. +:output+
      # * short is the short option form, e.g. "-o"
      # * long is the long option form, e.g. "--output FILE"
      # * class is the option value class, e.g. Integer
      # * description is the option usage, e.g. "Output file"
      # The option, long and description items are required; the short and class items can
      # be omitted.
      #
      # Each command line argument specification is an array in the form:
      #   [arg, text]
      # where:
      # * arg is the argument symbol, e.g. +:input+
      # * text is the usage message text, e.g. 'input', '[input]' or 'input ...' 
      # The arg and description items are required.
      #
      # Built-in options include the following:
      # * --help : print the help message and exit
      # * --version : print the version and exit
      # * --log FILE : log file
      # * --debug : print debug messages to the log
      # * --file FILE: configuration file containing other options
      # * --quiet: suppress printing messages to stdout
      # This class processes these built-in options, with the exception of +--version+,
      # which is a subclass responsibility. Subclasses are responsible for
      # processing any remaining options.
      #
      # @param [(<Symbol>, <String, Class>)] specs the arguments and options
      #   described above
      # @yield (see #run)
      # @yieldparam (see #run)
      def initialize(specs=[], &executor)
        @executor = executor
        @opt_specs, @arg_specs = specs.partition { |spec| spec[1][0, 1] == '-' }
        @opt_specs.concat(DEF_OPTS)
        super($0)
      end
  
      # Runs this command by calling the block given to this method, if provided,
      # otherwise the block given to {#initialize}
      # option or argument symbol => value hash.
      # @yield [hash] the command execution block
      # @yieldparam [{Symbol => Object}] hash the argument and option symbol => value hash
      def run
        # the option => value hash
        opts = get_opts
        # this base class's options
        handle_options(opts)
        # add the argument => value hash
        opts.merge!(get_args)
        # call the block
        block_given? ? yield(opts) : call_executor(opts)
      end
  
      private
      
      DEF_OPTS = [
        [:help, "-h", "--help", "Display this help message"],
        [:file, "--file FILE", "Configuration file containing other options"],
        [:log, "--log FILE", "Log file"],
        [:debug, "--debug", "Display debug log messages"],
        [:quiet, "-q", "--quiet", "Suppress printing messages to stdout"]
      ]
      
      def call_executor(opts)
         if @executor.nil? then raise CommandError.new("Command #{self} does not have an execution block") end
         @executor.call(opts)
      end
      
      # Collects the command line options.
      #
      # @return [{Symbol => Object}] the option => value hash 
      def get_opts
        opts = {}
        # the option parser
        OptionParser.new do |parser|
          arg_s = @arg_specs.map { |spec| spec[1] }.join(' ')
          parser.banner = "Usage: #{parser.program_name} [options] #{arg_s}"
          parser.separator ""
          parser.separator "Options:"
          opts = parse(parser)
          @usage = parser.help
        end
        opts
      end
  
      # Collects the non-option command line arguments.
      #
      # @return [{Symbol => Object}] the argument => value hash 
      def get_args
        return Hash::EMPTY_HASH if ARGV.empty?
        args = {}
        n = [ARGV.size, @arg_specs.size - 1].min
        n.times { |i| args[@arg_specs[i].first] = ARGV[i] }
        if n < ARGV.size then
          arg, form = @arg_specs.last
          if form.index('...') then
            args[arg] = ARGV[n..-1]
          elsif @arg_specs.size == ARGV.size then
            args[arg] = ARGV[n]
          else
            halt("Too many arguments", 1)
          end
        end
        args
      end
      
      # @param [OptionParser] parser the option parser
      # @return [{Symbol => Object}] the option => value hash
      def parse(parser)
        opts = {}
        @opt_specs.each do |opt, *spec|
          parser.on_tail(*spec) { |v| opts[opt] = v }
        end
        # build the option => value hash 
        parser.parse!
        opts
      end
      
      # Processes the built-in options.
      #
      # @param [{Symbol => Object}] the option => value hash
      def handle_options(opts)
        # if help, then print usage and exit
        if opts[:help] then halt end
        
        # open the log file
        log = opts[:log]
        debug = opts[:debug]
        if log then
          CaRuby::Log.instance.open(log, :debug => debug)
        elsif debug then
          logger.level = Logger::DEBUG
        end
        
        # if there is a file option, then load additional options from the file
        file = opts.delete(:file)
        if file then
          props = CaRuby::Properties.new(file)
          props.each { |opt, arg| ARGV << "--#{opt}" << arg }
          OptionParser.new do |p|
            opts.merge!(parse(p)) { |ov, nv| ov ? ov : nv }
          end
        end
      end
      
      # Prints the given error message and the program usage, then exits with status 1.
      def fail(message=nil)
        halt(message, 1)
      end
  
      # Prints the given message and program usage, then exits with the given status.
      def halt(message=nil, status=0)
        print(message) if message
        print(@usage)
        exit(status)
      end
    end
  end
end
