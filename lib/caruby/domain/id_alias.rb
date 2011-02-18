module CaRuby
  # Mix-in for Java classes which have an +id+ property.
  # Since +id+ is a reserved Ruby method, this mix-in defines an +identifier+ attribute
  # which fronts the +id+ property.
  module IdAlias
    # Returns the identifier.
    # This method delegates to the Java +id+ property reader method.
    #
    # @return [Integer] the identifier value
    def identifier
      getId
    end

    # Sets the identifier to the given value.
    # This method delegates to the Java +id+ property writer method.
    #
    # @param [Integer] value the value to set
    def identifier=(value)
      setId(value)
    end
  end
end