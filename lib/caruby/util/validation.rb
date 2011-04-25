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
