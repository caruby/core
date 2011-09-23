require 'json'

module CaRuby
  module JSON
    # JSON => {Resource} deserializer.
    module Deserializer
      # @param [String] json the JSON to deserialize
      # @return [Resource] the deserialized object
      def json_create(json)
        # Make the new object from the json data attribute => value hash.
        new(json['data'])
      end
    end
  end
end