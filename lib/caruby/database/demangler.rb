require 'jinx/resource/copy_visitor'
require 'jinx/metadata/introspector'

module CaRuby
  # Demangler restores the integrity of a caCORE search or save result. This class works
  # around the following caCORE problems:
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
  class Demangler
    def initialize
      # The proxy reference visitor.
      @ref_vstr = Jinx::ReferenceVisitor.new { |ref| ref.class.fetched_domain_attributes }
    end
     
    # If the given toxic caCORE search or save result argument is a caCORE
    # +SpringProxy+, then this method returns the target domain object.
    # If the toxic argument is a caCORE +ListProxy+, then this method
    # returns an Array of the target domain objects.
    # Otherwise, this method returns the unchanged argument. 
    #
    # @param toxic the application service search or save result
    # @return [Resource, <Resource>] the target domain object or objects.
    def demangle(toxic)
      return toxic unless proxy?(toxic)
      restore_target(ProxyWrapper.wrap(toxic))
    end
    
    private
    
    # @param toxic the caCORE search or save result
    # @return [Boolean] whether the result is a caCORE proxy list or object
    def proxy?(toxic)
      # The list proxy class.
      @list_pxy_cls ||= Java::gov.nih.nci.system.client.proxy.ListProxy rescue nil
      # The object proxy class.
      @obj_pxy_cls ||= Java::org.springframework.aop.SpringProxy rescue nil
      if toxic.collection? then
        !!@list_pxy_cls and @list_pxy_cls === toxic
      else
        !!@obj_pxy_cls and @obj_pxy_cls === toxic
      end
    end
    
    # Makes a new domain object with content copied recursively from the given wrapper's proxy
    # target fetched object graph.
    #
    # @param [ProxyWrapper, <ProxyWrapper>] wrapper the proxy wrapper or wrappers to restore
    # @return [Resource, <Resource] the new domain object or objects
    def restore_target(wrapper)
      wrapper.collection? ? wrapper.map { |item| restore_target(item) } : wrapper.restore_target
    end
  end
end

