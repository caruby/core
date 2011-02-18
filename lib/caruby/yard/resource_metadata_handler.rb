class ResourceMetadataHandler < YARD::Handlers::Ruby::Legacy::AttributeHandler
  handles method_call(/\Aqualify_attribute\b/)
  namespace_only

  def process
    push_state(:scope => :class) { super }
  end
end