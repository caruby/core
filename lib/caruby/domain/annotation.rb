require 'caruby/resource'

module CaRuby
  # The Annotation module marks a domain object as an Annotation.
  module Annotation
    include Resource

    # Dynamically creates a new annotable owner attribute with the given symbol if symbol is an annotatable owner attribute
    # accessor method.
    #
    # @see #attribute_missing
    def method_missing(symbol, *args)
      name = symbol.to_s
      # remove trailing assignment = if present
      name.chop! if name =~ /=$/
      # try to make the owner attribute
      self.class.attribute_metadata(name.to_sym)
      # if we reached here, then the owner was created so verify and call the new method
      raise NoMethodError.new("#{name.demodulize} owner attribute #{name} created but accessor method not found: #{symbol}") unless method_defined?(symbol)
      send(symbol, *args)
    end
  end
end
