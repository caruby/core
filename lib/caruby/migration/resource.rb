require 'caruby/resource'
require 'caruby/migration/migratable'

module CaRuby
  module Resource
    include Migratable
  end
end