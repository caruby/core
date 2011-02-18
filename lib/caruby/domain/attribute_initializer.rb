module CaRuby
  module AttributeInitializer
    # Initializes a new instance of this Resource class with optional attribute => value hash
    # @param [{Symbol => Object}] the optional attribute => value hash
    # @return 
    def initialize(hash=nil)
      super()
      if hash then
        unless Hashable === hash then
          raise ArgumentError.new("#{qp} initializer argument type not supported: #{hash.class.qp}")
        end
        merge_attributes(hash)
      end
    end
  end
end