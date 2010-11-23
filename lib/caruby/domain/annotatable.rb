require 'caruby/resource'

module CaRuby
  # The Annotatable module marks a domain class as an anchor which holds at least one annotation attribute.
  module Annotatable
    include Resource

    # Dynamically creates a new annotation reference method with the given symbol if symbol is the camelized form of a
    # class in one of the Annotatable class's annotation modules.
    def method_missing(symbol, *args)
      name = symbol.to_s
      # remove trailing assignment = if present
      name.chop! if name =~ /=$/
      # the class with the camelized form of the name
      klass = self.class.annotation_class(name.camelize)
      # delegate to super to print an error if no class
      super if klass.nil?
      # add the annotation attribute
      klass.add_annotation(self.class)
      raise NotImplementedError.new("#{self.class.qp} annotation method not created: #{symbol}") unless respond_to?(symbol)
      #call the annotation attribute method
      send(symbol, *args)
    end
  end
end
