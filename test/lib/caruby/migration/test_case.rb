LOG_FILE = 'test/results/log/migration.log'

require File.join(File.dirname(__FILE__), '..', 'test_case')
require 'caruby/domain/uniquify'
require 'caruby/migration/migrator'

module CaRuby
  module MigrationTestCase
    include CaRuby::TestCase

    #@param [String] fixtures the fixtures directory
    def setup(fixtures)
      @fixtures = fixtures
      # Clear the uniquifier for this migration.
      CaRuby::ResourceUniquifier.instance.clear
    end

    ## MIGRATION TEST UTILITY METHODS ##

    private

    # Runs a migrator on the given input fixture and options.
    #
    # @param (see #create_migrator)
    # @option (see #create_migrator)
    def migrate_to_database(fixture, opts={}, &verifier)
      mgtr = create_migrator(fixture, opts)
      logger.debug { "Migration test migrating #{fixture} fixture..." }
      mgtr.migrate_to_database(&verifier)
      logger.debug { "Migration test migrated #{fixture} fixture." }
    end

    # Creates a new Migrator for the given fixture with the given options.
    # If a factory block is provided, then that factory is called to make a new
    # Migrator instance. Otherwise, {CaTissue::Migrator#initialize} makes the instance.
    #
    # If there is no :input option, then the migration input is set to the
    # _fixture_.+csv+ file in the {#initialize} fixtures directory.
    #
    # @param [Symbol] fixture the migration test fixture
    # @param [{Symbol => Object}] opts (see CaTissue::Migrator#initialize)
    # @option (see CaTissue::Migrator#initialize)
    # @return [CaTissue::Migrator]
    # @yield [opts] the optional Migrator factory
    def create_migrator(fixture, opts={}, &factory)
      opts[:quiet] = true
      opts[:input] ||= File.join(@fixtures, fixture.to_s + '.csv')
      block_given? ? yield(opts) : CaTissue::Migrator.new(opts)
    end

    # Verifies that the given test fixture is successfully migrated.
    # Each migrated target object is validated using {CaTissue::TestCase#verify_saved}.
    # In addition, if a verifier block is given to this method, then that block is
    # called on the target migration object, or nil if no target was migrated.
    # Supported options are described in {CaTissue::Migrator#migrate}.
    #
    # @param (see #verify_target)
    # @option (see #verify_target)
    # @yield (see #verify_target)
    # @yieldparam (see #verify_target)
    def verify_save(fixture, opts={})
      logger.debug { "Migrating the #{fixture} test fixture..." }
      opts[:unique] = true unless opts.has_key?(:unique)
      migrate_to_database(fixture, opts) do |tgt|
        verify_saved(tgt)
        yield tgt if block_given?
      end
    end

    # Verifies the given fixture migration.
    # Each migrated target object is validated using {#validate_target}.
    # The target is migrated but not stored.
    #
    # @param [Symbol] fixture the test fixture to verify
    # @param [<Symbol>] opts the migration options
    # @option (see CaTissue::Migrator#migrate)
    # @yield [target] verifies the given target
    # @yieldparam [Resource] target the domain object to verify
    def verify_target(fixture, opts={}, &verifier)
      opts[:unique] ||= false
      create_migrator(fixture, opts).migrate { |tgt| validate_target(tgt, &verifier) }
    end

    # Validates that the given target was successfully migrated.
    # If a target was migrated, then this method calls {CaTissue::TestCase#verify_defaults}
    # to confirm that the target can be stored.
    # In addition, if a block is given to this method then the block is called on the
    # (possibly nil) migration target.
    #
    # @param [Resource] target the domain object to verify
    # @yield (see #verify_target)
    # @yieldparam (see #verify_target)
    def validate_target(target)
      assert_not_nil(target, "Missing target")
      logger.debug { "Validating migration target #{target}..." }
      verify_defaults(target) if target
      yield target if block_given?
      logger.debug { "Validated migration target #{target}." }
      target
    end
  end
end