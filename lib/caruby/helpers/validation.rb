module CaRuby
  # Raised when an object fails a validation test.
  class ValidationError < RuntimeError; end
end

class Object
  # Returns whether this object is nil, false, empty, or a whitespace string.
  # This method is borrowed from Rails ActiveSupport.
  #
  # @example
  #   ''.blank? => true
  #   nil.blank? => true
  #   false.blank? => true
  #   [].blank? => true
  #   [[]].blank? => false
  # @return [Boolean] whether this object is nil, false, empty, or a whitespace string
  # @see {#nil_or_empty?}
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end

  # Returns whether this object is nil, empty, or a whitespace string.
  # This method differs from {#blank?} in that +false+ is an allowed value.
  #
  # @example
  #   ''.nil_or_empty? => true
  #   nil.nil_or_empty? => true
  #   false.nil_or_empty? => false
  # @return [Boolean] whether this object is nil, empty, or a whitespace string
  def nil_or_empty?
    blank? and self != false
  end
end
