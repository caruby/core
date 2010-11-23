module JavaImport
  # AnnotationClass extends a domain class for an annotation class scoped by an annotation module.
  # The extended class must contain the +@anchor_class+ and +@annotation_module+ instance variables.
  module AnnotationClass

    # Dynamically creates a new reference attribute if the given attribute symbol is the underscore
    # form of this Annotation's anchor class.
    #
    #@param [Symbol] attribute the missing attribute 
    def attribute_missing(attribute)
      # delegate to super to print an error if no class
      super unless attribute.to_s == anchor_class.qp.underscore
      # add the annotation attribute to the anchor class and the anchor attribute to this class
      anchor_class.add_annotation(self)
    end

    # @return [Class] the annotated class
    def anchor_class
      @anchor_class
    end

    # @return [Module] the module which scopes this AnnotationClass
    def annotation_module
      @annotation_module
    end
  end
end