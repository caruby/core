require 'singleton'

# the minimal mock CaRuby::Database functionality
require 'caruby/database/persistifier'

module ClinicalTrials
  # The example mock database.
  class Database < CaRuby::Database
    include Singleton, CaRuby::Database::Persistifier
  end
end