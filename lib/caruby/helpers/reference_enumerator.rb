require 'caruby/helpers/collection'

module CaRuby
  # ReferenceEnumerator iterators over attribute references.
  class ReferenceEnumerator
    include Enumerable
    
    # @param on the object containing the references
    # @param [<Symbol>] the attributes to iterate
    def initialize(on, attributes)
      @on = on
      @attrs = attributes
    end
    
    # @yield [ref] the block to execute on the referenced value
    # @yieldparam ref the referenced value
    def each(&block)
      @attrs.each { |rattr| @on.send(rattr).enumerate(&block) }
    end
  end
end