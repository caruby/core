# Raised when an object fails a validation test.
class ValidationError < RuntimeError; end

class Object
  # Returns whether this object is nil, false, empty, or a whitespace string.
  # For example, "", "   ", +nil+, [], and {} are blank.
  #
  # This method is borrowed from Rails ActiveSupport.
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end

  # Returns whether this object is nil, empty, or a whitespace string.
  # For example, "", "   ", +nil+, [], and {} return +true+.
  #
  # This method differs from blank? in that +false+ is an allowed value.
  def nil_or_empty?
    nil? or (respond_to?(:empty?) and empty?)
  end
end

module Validation
  # A Validator is a procedure which responds to the +validate(value)+ method.
  class Validator < Proc
    alias :validate :call
  end

  # Validates that each key value in the value_type_assns value => type hash is an instance of the associated class.
  #
  # Raises ValidationError if the value is missing.
  # Raises TypeError if the value is not the specified type.
  def validate_type(value_type_assns)
    TYPE_VALIDATOR.validate(value_type_assns)
  end

  private

  def self.create_type_validator
    Validator.new do |value_type_assns|
      value_type_assns.each do |value, type|
        raise ArgumentError.new("Missing #{type.name} argument") if value.nil?
        raise TypeError.new("Unsupported argument type; expected: #{type.name} found: #{value.class.name}") unless type === value
      end
    end
  end

  TYPE_VALIDATOR = create_type_validator
end