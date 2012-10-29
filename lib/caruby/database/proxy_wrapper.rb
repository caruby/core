require 'jinx/resource/mergeable'
require 'jinx/resource/copy_visitor'
require 'jinx/metadata/introspector'

module CaRuby
  # ProxyWrapper wraps a caCORE serach result proxy to work around the caCORE
  # problems described in {Demangler}
  # 
  # @quirk caCORE 4.x The caCORE 4+ search result returns a mysterious ListProxy whose
  #   iterator and content is broken in JRuby. The only feature that works is the result
  #   size. An iterator on a non-empty list silently returns without visiting an item
  #   in the list. List items are, however, accessible by index. The caRuby work-around
  #   is to copy the query result items, referenced by index rather than an iterator,
  #   into an array.
  #
  # @quirk caCORE 4.x The caCORE 4+ search result list item is an instance of a broken
  #   proxy class with an empty class name. Furthermore, a domain object reference property
  #   reader method returns a different instance each time it is called. This causes the
  #   caRuby object merge to set domain property values to a corrupted proxy rather than
  #   a valid consistent domain object  reference. This aberrant behavior occurs with JRuby,
  #   but not in a caTissue Java API program. The discrepant behavior probably results from
  #   caCORE wrapping a byte-code injection object which hoses the object for a non-caCORE
  #   Java environment. The caRuby work-around is to copy each query result ite into a
  #   {SlightlyLessCorruptedCaCOREProxy} with a special-purpose unproxy visitor.
  #
  # The ProxyWrapper instance +class+ method is overridden to return the proxy target
  # JRuby wrapper class. Since each caCORE proxy property reader method return an unstable
  # value, ProxyWrapper implements the target class reader methods by retaining the proxy
  # property value in a stable value hash.
  class ProxyWrapper
    include Jinx::Mergeable
    
    # Wraps the given caCORE 4.x proxy or proxies in {ProxyWrapper}.
    # If the given toxic argument is a ListProxy, then this method returns an Array
    # of wrapped objects, otherwise this method wraps the given proxy. 
    #
    # @quirk caRuby A caRuby proxy collection breaks the JRuby iterator. Work-around is
    #   to iterate using an index instead.
    #
    # @quirk caRuby The caRuby proxies introduced in caCORE 4.0 sometimes omit the
    #   identifier in the save cascade result, e.g. a caTissue SCG save does not set
    #   the cascaded action application identifier. These partial results cannot be
    #   used in caRuby, since there is no means of fetching them without a secondary
    #   key, which is not always available. caRuby corrects this by omitting the
    #   malformed proxies in this wrap method. The malformed properties are marked
    #   as +:fetch_saved+, which refetches the saved object to pick up the well-formed
    #   proxies. 
    #
    # @param proxy the application service search or save result
    # @return [ProxyWrapper, <ProxyWrapper>] the wrapped result
    def self.wrap(proxy)
      if proxy.collection? then
        # the wrapped collection
        array = []
        # Iterate using an index, since the proxy collection iterator is broken.
        0.upto(proxy.size - 1) do |i|
          # Skip the proxy if it does not have an identifier.
          mbr = wrap(proxy[i]) || next
          array << mbr
        end
        unless array.empty? then
          logger.debug { "Wrapped the caCORE proxy list with #{array.qp}." }
        end
        array
      elsif proxy.getId then
        klass = Class.to_ruby(proxy.target_class)
        wrapped = @subclasses[klass].new(proxy)
        logger.debug { "Wrapped the caCORE #{klass.qp} proxy with #{wrapped}." }
        wrapped
      else
        logger.debug { "Skipping the malformed caCORE #{proxy.target_class.qp} proxy since it does not have an identifier." }
        nil
      end
    end
    
    # The proxy => target copy visitor.
    @@rst_vstr = Jinx::CopyVisitor.new(:copier => Proc.new { |pxy| pxy.restore_target_object }) do |pxy|
      pxy.target_class.fetched_domain_attributes
    end
    
    # Makes a new domain object with content copied recursively from this wrapper's proxy
    # target fetched object graph.
    #
    # @return [Resource] a new target domain object for the proxy wrapped by this {ProxyWrapper}
    def restore_target
      @@rst_vstr.visit(self)
    end
    
    # @return [Class] the proxy target domain object class
    def target_class
      self.class.target_class
    end
    
    alias :domain_class :target_class
    
    # @return [Integer] a content hash based on the proxy target class and identifier
    def hash
      id = @proxy.identifier
      id ? id + (31 * (target_class.hash + 7)) : super
    end

    # @return [ProxyWrapper] other whether the other object is a {ProxyWrapper} and the respective
    # proxy identifier and target class are equal
    def ==(other)
      id = @proxy.identifier
      return super unless id and ProxyWrapper === other
      target_class == other.target_class and id == other.identifier
    end
    
    def to_s
      "ProxyWrapper@#{object_id}{#{target_class.qp}{:identifier => #{@proxy.identifier.qp}}}"
    end
    
    # Makes a new domain object with non-domain property values copied from this wrapper's
    # proxy target object.
    #
    # @return (see #restore_target)
    def restore_target_object
      tgt = target_class.new.merge(self)
      logger.debug { "Copied #{self} to the restored POJO target #{tgt}." }
      tgt
    end
    
    private
    
    # The Targeted mix-in extends a ProxyWrapper subclass with a {#target_class} delegator.
    module Targeted
      # @return [Class] the proxy target class
      attr_reader :target_class
      
      # @return [String] +CaRuby::ProxyClass{+**target_class**+}+
      def name
        "#{superclass.name}{#{@target_class}}"
      end
      
      private
      
      # Delegates the class methods to the {#target_class}.
      def method_missing(sym, *args)
        begin
          @target_class.send(sym, *args)
        rescue NoMethodError
          super
        end
      end
    end
    
    # There is a ProxyWrapper subclass for each proxy target class. The subclass is extended
    # with the {Targeted} mix-in.
    @subclasses = Jinx::LazyHash.new do |klass|
      Jinx::Introspector.ensure_introspected(klass)
      pklass = Class.new(self)
      pklass.instance_eval do
        @target_class = klass
        extend Targeted
      end
      pklass
    end

    def initialize(proxy)
      if proxy.getId.nil? then
        raise DatabaseError.new("The caCORE #{self.class.target_class.qp} proxy result does not have an identifier.")
      end
      @proxy = proxy
      @vh = Jinx::LazyHash.new do |prop|
        begin
          v = @proxy.send(prop.java_reader)
        rescue NoMethodError
          logger.error("The caCORE #{target_class} proxy #{@proxy.qp} does not implement the #{prop} method: - #{$!}")
          raise
        end
        if v and prop.domain? then
          logger.debug { "Wrapping the #{self} #{prop} reference..." }
          ProxyWrapper.wrap(v)
        else
          v
        end
      end
    end
    
    # @param [Symbol] sym the missing method
    # @param [Array] args the method arguments
    # @return the wrapped proxy property value
    # @raise [NoSuchMethodError] if the proxy does not have the given proxy attribute
    def method_missing(sym, *args)
      begin
        prop = target_class.property(sym)
      rescue NameError
        raise NameError.new("Proxy target property not found: #{target_class.qp}.#{sym}.")
      end
      return super unless prop.java_property?
      @vh[prop]
    end
  end
end

