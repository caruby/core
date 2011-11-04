module CaRuby
  module Shim
    # Declares the given {Resource} classes which will be dynamically modified.
    # This method auto-loads the classes, if necessary.
    def shims(*classes)
      # nothing to do, since all this method does is ensure that the arguments are auto-loaded when they are referenced
    end
  end
end
