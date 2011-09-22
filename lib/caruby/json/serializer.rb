module CaRuby
  module JSON
    # {Resource} => JSON serializer.
    module Serializer
      # @param args the JSON serialization options
      # @return [String] the JSON representation of this {Resource}
      def to_json(*args)
        database.lazy_loader.disable do
          # The JSON class must be scoped by the domain module, not the Java package, in order
          # to recognize the Resource JSON hooks.
          # The data is the attribute => value hash.
         {'json_class' => [self.class.domain_module, self.class.name.demodulize].join('::'),
            'data' => value_hash(self.class.nonowner_attributes)
          }.to_json(*args)
        end
      end
    end
  end
end

module Enumerable
  # @param args the JSON serialization options
  # @return [String] the JSON representation of this Enumerable as an array
  def to_json(*args)
    to_a.to_json(*args)
  end
end