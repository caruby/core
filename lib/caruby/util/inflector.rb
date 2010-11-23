require 'caruby/active_support/inflector'

class String
  # @param [Numeric] quantity the amount qualifier
  # @return this String qualified by a plural if the quantity is not 1
  # @example
  #   "rose".quantify(3) #=> "roses"
  #   "rose".quantify(1 #=> "rose"
  def quantify(quantity)
    raise ArgumentError.new("Missing quantity argument") if quantity.nil?
    "#{quantity} #{quantity == 1 ? self : pluralize}"
  end
  
  # @return this String with the first letter capitalized and other letters preserved.
  # @example
  #   "rosesAreRed".capitalize_first #=> "RosesAreRed"
  def capitalize_first
    sub(/(?:^)(.)/) { $1.upcase }
  end
end