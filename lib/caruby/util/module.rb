class Module
  # Returns the class or module with name in the parent module.
  # If parent is nil, then name is looked up in the global context.
  # Otherwise, this method returns {#module_with_name}.
  def self.module_with_name(parent, name)
    return parent.module_with_name(name) if parent
    begin
      constant = eval(name)
    rescue Exception
      return
    end
    constant if constant.is_a?(Module)
  end

  # Returns the class or module with name in this module.
  # name can qualified by parent modules, e.g. +MyApp::Person+.
  # If name cannot be resolved as a Module, then this method returns nil.
  def module_with_name(name)
    begin
      constant = name.split('::').inject(parent) { |parent, name| parent.const_get(name) }
    rescue Exception
      return
    end
    constant if constant.is_a?(Module)
  end

  # Returns the class with name in this module.
  # name can qualified by parent modules, e.g. +MyApp::Person+.
  # If name cannot be resolved as a Class, then this method returns nil.
  def class_with_name
    mod = module_with_name
    mod if mod.is_a?(Class)
  end
end