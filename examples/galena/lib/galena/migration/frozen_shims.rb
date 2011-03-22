# load the defaults file in the seed directory
require File.join(File.dirname(__FILE__), '..', 'seed', 'defaults')

module CaTissue
  # Declares the classes modified for migration.
  shims TissueSpecimen, CollectionProtocolRegistration, StorageContainer 
  
  class StorageContainer
    # Creates the migrated box in the database, if necessary.
    #
    # @param (see CaRuby::Migratable#migrate)
    def migrate(row, migrated)
      super
      find or create_galena_box
    end
    
    private

    # Creates a new box of type {Galena::Seed::Defaults#box_type} in a freezer of type
    # {Galena::Seed::Defaults#freezer_type}.
    # 
    # @return [StorageContainer] the new box
    def create_galena_box
      defs = Galena::Seed.defaults
      self.storage_type = defs.box_type
      site = defs.tissue_bank
      # A freezer with a slot for the box.
      frz = defs.freezer_type.find_available(site, :create)
      if frz.nil? then raise CaRuby::MigrationError.new("Freezer not available to place #{self}") end
      # Add this box to the first open slot in the first unfilled rack in the freezer.
      frz << self
    end
  end
end