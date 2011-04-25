require 'set'
require 'date'
require 'pp'
require 'stringio'
require 'caruby/util/options'
require 'caruby/util/collection'
require 'caruby/util/inflector'

class PrettyPrint
  # Fixes the standard prettyprint gem SingleLine to add an output accessor and an optional output argument to {#initialize}.
  class SingleLine
    attr_reader :output

    alias :base__initialize :initialize
    private :base__initialize

    # Allow output to be optional, defaulting to ''
    def initialize(output='', maxwidth=nil, newline=nil)
      base__initialize(output, maxwidth, newline)
    end
  end
end

# A PrintWrapper prints arguments by calling a printer proc.
class PrintWrapper < Proc
  # Creates a new PrintWrapper on the given arguments.
  def initialize(*args)
    super()
    @args = args
  end

  # Sets the arguments to wrap with this wrapper's print block and returns self.
  def wrap(*args)
    @args = args
    self
  end

  # Calls this PrintWrapper's print procedure on its arguments.
  def to_s
    @args.empty? ? 'nil' : call(*@args)
  end

  alias :inspect :to_s
end

class Object
  # Prints this object's class demodulized name and object id.
  def print_class_and_id
    "#{self.class.qp}@#{object_id}"
  end

  # qp, an abbreviation for quick-print, calls {#print_class_and_id} in this base implementation.
  alias :qp :print_class_and_id

  # Formats this object as a String with PrettyPrint.
  # If the :single_line option is set, then the output is printed to a single line.
  def pp_s(options=nil)
    s = StringIO.new
    if Options.get(:single_line, options) then
      PP.singleline_pp(self, s)
    else
      PP.pp(self, s)
    end
    s.rewind
    s.read.chomp
  end
end

class Numeric
  # qp, an abbreviation for quick-print, is an alias for {#to_s} in this primitive class.
  alias :qp :to_s
end

class String
  # qp, an abbreviation for quick-print, is an alias for {#to_s} in this primitive class.
  alias :qp :to_s
end

class TrueClass
  # qp, an abbreviation for quick-print, is an alias for {#to_s} in this primitive class.
  alias :qp :to_s
end

class FalseClass
  # qp, an abbreviation for quick-print, is an alias for {#to_s} in this primitive class.
  alias :qp :to_s
end

class NilClass
  # qp, an abbreviation for quick-print, is an alias for {#inspect} in this NilClass.
  alias :qp :inspect
end

class Symbol
  # qp, an abbreviation for quick-print, is an alias for {#inspect} in this Symbol class.
  alias :qp :inspect
end

class Module
  # qp, an abbreviation for quick-print, prints this module's name unqualified by a parent module prefix.
  def qp
    name[/\w+$/]
  end
end

module Enumerable
  # qp, short for quick-print, prints a collection Enumerable with a filter that calls qp on each item.
  # Non-collection Enumerables delegate to the superclass method.
  def qp
    wrap { |item| item.qp }.pp_s
  end

  # If the transformer block is given to this method, then the transformer block to each
  # enumerated item before pretty-printing the result.
  def pp_s(options=nil, &transformer)
    # delegate to Object if no block
    return super(options) unless block_given?
    # make a print wrapper
    wrapper = PrintWrapper.new { |item| yield item }
    # print using the wrapper on each item
    wrap { |item| wrapper.wrap(item) }.pp_s(options)
  end

  # Pretty-prints the content within brackets, as is done by the Array pretty printer.
  def pretty_print(q)
    q.group(1, '[', ']') {
      q.seplist(self) { |v|
        q.pp v
      }
    }
  end

  # Pretty-prints the cycle within brackets, as is done by the Array pretty printer.
  def pretty_print_cycle(q)
    q.text(empty? ? '[]' : '[...]')
  end
end

module Hashable
  # qp, short for quick-print, prints this Hashable with a filter that calls qp on each key and value.
  def qp
    qph = {}
    each { |k, v| qph[k.qp] = v.qp }
    qph.pp_s
  end

  def pretty_print(q)
    Hash === self ? q.pp_hash(self) : q.pp_hash(to_hash)
  end

  def pretty_print_cycle(q)
    q.text(empty? ? '{}' : '{...}')
  end
end

class String
  # Pretty-prints this String using the Object pretty_print rather than Enumerable pretty_print.
  def pretty_print(q)
    q.text self
  end
end

class DateTime
  def pretty_print(q)
    q.text(strftime)
  end
  
  # qp, an abbreviation for quick-print, is an alias for {#to_s} in this primitive class.
  alias :qp :to_s
end

class Set
  # Formats this set using {Enumerable#pretty_print}.
  def pretty_print(q)
    # mark this object as visited; this fragment is inferred from pp.rb and is necessary to detect a cycle
    Thread.current[:__inspect_key__] << __id__
    to_a.pretty_print(q)
  end

  # The pp.rb default pretty printing method for general objects that are detected as part of a cycle.
  def pretty_print_cycle(q)
    to_a.pretty_print_cycle(q)
  end
end
