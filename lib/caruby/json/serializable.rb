require 'jinx/json/serializable'

module CaRuby
  module JSON
    module Serializable
      include Jinx::JSON::Serializable
      
      # This method disables lazy-loading before delegating to Jinx.
      #
      # @param [State, Hash, nil] state the JSON state or serialization options
      # @return [String] the JSON representation of this {Jinx::Resource}
      def to_json(state=nil)
        fetched? ? super : do_without_lazy_loader { super }
      end
    end
  end
end
