require 'jinx/json/serializable'

module CaRuby
  module JSON
    # {CaRuby::Resource} => JSON serializer.
    module Serializable
      include Jinx::JSON::Serializable
      
      # @param args the JSON serialization options
      # @return [String] the JSON representation of this {Jinx::Resource}
      def to_json(*args)
        database.lazy_loader.disable { super }
      end
    end
  end
end