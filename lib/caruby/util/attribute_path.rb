require 'caruby/util/validation'

# An AttributePath encapsulates an array of attributes that can be evaluated on a source object.
class AttributePath < Array
  # Creates an AttributePath from the path Array, String or Symbol. A path string is a period-delimited sequence
  # of attributes, e.g. +person.name+.
  def initialize(path)
    raise ArgumentError.new("Path empty") if path.nil_or_empty?
    # standardize the argument as a symbol array
    attributes = case path
    when Symbol then
      [path]
    when String then
      path.split('.').map { |name| name.to_sym }
    when Array then
      path.map { |name| name.to_sym }
    else
      raise ArgumentError.new("Argument type unsupported - expected Symbol, String or Array; found #{path.class}")
    end
    # make the array
    super(attributes)
  end

  # Returns the result of evaluating this evaluator's attribute path on the source object.
  # If the evaluation results in a migratable object, then that object is migrated.
  def evaluate(source)
    # call the attribute path as far as possible
    inject(source) do |current, attr|
      return if current.nil?
      evaluate_attribute(attr, current)
    end
  end

  # Returns the result of evaluating attribute on the source object.
  # If attr is +self+, then the source object is returned.
  def evaluate_attribute(attr, source)
    # call the attribute path as far as possible
    attr == :self ? source : source.send(attr)
  end

  def to_s
    join('.')
  end
end
