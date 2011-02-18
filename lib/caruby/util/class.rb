require 'enumerator'

class Class
  # Returns an Enumerable on this class and its ancestors.
  def class_hierarchy
    @class__hierarchy ||= Enumerable::Enumerator.new(self, :each_class_in_hierarchy)
  end

  # Returns this class's superclass, thereby enabling class ranges, e.g.
  #   class A; end
  #   class B < A; end
  #   (B..Object).to_a #=> [B, A, Object]
  alias :succ :superclass

  private

  # Creates an alias for each accessor method of the given attribute.
  #
  # @example
  #   class Person
  #    attr_reader :social_security_number
  #    attr_accessor :postal_code
  #    define_attribute_alias(:ssn, :social_security_number)
  #    define_attribute_alias(:zip_code, :postal_code)
  #   end
  #   Person.method_defined?(:ssn) #=> true
  #   Person.method_defined?(:ssn=) #=> false
  #   Person.method_defined?(:zip_code) #=> true
  #   Person.method_defined?(:zip_code=) #=> true
  def define_attribute_alias(aliaz, attribute)
    alias_method(aliaz, attribute) if method_defined?(attribute)
    writer = "#{attribute}=".to_sym
    alias_method("#{aliaz}=".to_sym, writer) if method_defined?(writer)
  end

  # Creates new accessor methods for each _method_ => _original_ hash entry.
  # The new _method_ offsets the existing Number _original_ attribute value by the given
  # offset (default -1).
  #
  # @example
  #   class OneBased
  #     attr_accessor :index
  #     offset_attr_accessor :zero_based_index => :index
  #   end
  #@param [{Symbol => Symbol}] hash the offset => original method hash
  #@param [Integer, nil] offset the offset amount (default is -1) 
  def offset_attr_accessor(hash, offset=nil)
    offset ||= -1
    hash.each do |method, original|
      define_method(method) { value = send(original); value + offset if value } if method_defined?(original)
      original_writer = "#{original}=".to_sym
      if method_defined?(original_writer) then
        define_method("#{method}=".to_sym) do |value|
          adjusted = value - offset if value
          send(original_writer, adjusted)
        end
      end
    end
  end

  # Defines an instance variable accessor attribute whose reader calls the block given
  # to this method to create a new instance variable on demand, if necessary.
  #
  # For example, the declaration
  #   class AlertHandler
  #     attr_create_on_demand_accessor(:pings) { Array.new }
  #   end
  # is equivalent to:
  #   class AlertHandler
  #     attr_writer :pings
  #     def pings
  #       instance_variable_defined?(@pings) ? @pings : Array.new
  #     end
  #   end
  #
  # This method is useful either as a short-hand for the create-on-demand idiom
  # as shown in the example above, or when it is desirable to dynamically add a
  # mix-in attribute to a class at runtime whose name is not known when the class
  # is defined.
  #
  # @example
  #   class AlertHandler
  #     def self.handle(alert)
  #       attr_create_on_demand_accessor(alert) { AlertQueue.new }
  #     end
  #   end
  #   ...
  #   AlertHandler.handle(:pings)
  #   AlertHandler.new.pings #=> empty AlertQueue
  #
  # @param [Symbol] symbol the attribute to define
  # @yield [obj] factory to create the new attribute value for the given instance
  # @yieldparam obj the class instance for which the attribute will be set
  def attr_create_on_demand_accessor(symbol)
    attr_writer(symbol)
    wtr = "#{symbol}=".to_sym
    iv = "@#{symbol}".to_sym
    # the attribute reader creates a new proxy on demand
    define_method(symbol) do
      instance_variable_defined?(iv) ? instance_variable_get(iv) : send(wtr, yield(self))
    end
  end

  # Enumerates each class in the hierarchy.
  #
  # @yield [klass] the enumeration block
  # @yieldparam [Class] klass the class in the hierarchy
  def each_class_in_hierarchy
    current = self
    until current.nil?
      yield current
      current = current.superclass
    end
  end

  # Redefines method using the given block. The block argument is a new alias for the old method.
  # The block creates a proc which implements the new method body.
  #
  # @example
  #   redefine_method(:ssn) { |old_method| lambda { send(old_method).delete('-').to_i } }
  # @return [Symbol] an alias to the old method implementation
  def redefine_method(method)
    # make a new alias id method__base for the existing method.
    # disambiguate with a counter suffix if necessary.
    counter = 2
    # make a valid alias base
    old, eq = /^([^=]*)(=)?$/.match(method.to_s).captures
    old.tr!('|', 'or')
    old.tr!('&', 'and')
    old.tr!('+', 'plus')
    old.tr!('*', 'mult')
    old.tr!('/', 'div')
    old.gsub!(/[^\w]/, 'op')
    base = "redefined__#{old}"
    old_id = "#{base}#{eq}".to_sym
    while method_defined?(old_id)
      base = "#{base}#{counter}"
      old_id = "#{base}#{eq}".to_sym
      counter = counter + 1
    end
    alias_method(old_id, method)
    body = yield old_id
    define_method(method, body)
    old_id
  end
end