require 'singleton'

# the minimal mock CaRuby::Database functionality
require 'caruby/database/persistifier'

module ClinicalTrials
  # The example mock database.
  class Database < CaRuby::Database
    include Singleton, CaRuby::Database::Persistifier

    # @return a new instance of the target attribute class
    # @see {CaRuby::Reader#fetch_association}
    def fetch_association(obj, attribute)
      attr_md = obj.class.attribute_metadata(attribute)
      ref = attr_md.type.new
      attr_md.collection? ? [ref] : ref
    end
  end
end