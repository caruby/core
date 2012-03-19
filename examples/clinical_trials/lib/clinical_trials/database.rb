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
      pa = obj.class.property(attribute)
      ref = pa.type.new
      pa.collection? ? [ref] : ref
    end
  end
end