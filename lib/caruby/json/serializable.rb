require 'jinx/json/serializable'

module CaRuby
  module JSON
    module Serializable
      include Jinx::JSON::Serializable
      
      private
      
      # This method disables lazy-loading before delegating to Jinx.
      #
      # @param [<Resource>] visited the serialized objects
      # @return [{Symbol => Object}] the serializable value hash
      def json_value_hash(visited)
        fetched? ? super : do_without_lazy_loader { super }
      end
    end
  end
end
