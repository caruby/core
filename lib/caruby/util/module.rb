class Module
  # Returns the class or module with the given name defined in this module.
  # The name can qualified by parent modules, e.g. +MyApp::Person+.
  # If name cannot be resolved as a Module, then this method returns nil.
  #
  # @param [String] the class name
  # @return [Module, nil] the class or module defined in this module, or nil if none 
  def module_with_name(name)
    name.split('::').inject(self) { |parent, part| parent.const_get(part) } rescue nil
  end
  
  # @example
  #   A::B.parent_module #=> A
  # @return [Module] this module's definition context
  def parent_module
    Kernel.module_with_name(name.split('::')[0..-2].join('::'))
  end
end