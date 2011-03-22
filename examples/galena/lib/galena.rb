# The caRuby Tissue Galena example module.
module Galena
  # @param [String] the path (without wildcards) of the desired file relative to the gem root directory
  # @return [String, nil] the file in this gem which matches the given path
  def self.resource(path)
    File.expand_path(File.join(File.dirname(__FILE__), '..', path))
  end
end