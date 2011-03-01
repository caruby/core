The caRuby Tissue Migrator imports input CSV files into caTissue. A migration is performed as follows:

1. [Install](/kb/getting-started/how-do-i-install-caruby) caruby-tissue.

2. Extract a CSV file from the source tissue repository system.

3. Peruse the caRuby Galena migration example. Enter the following to locate the example:

        crtexample

   Copy the example to a location of your choosing. Use this example as a starting point for your
   own migration.

4. Create a mapping file that associates the input fields with the corresponding caTissue properties, e.g.:
        # The input MRN field is the caTissue PMI MRN and Participant last name.
        MRN: ParticipantMedicalIdentifier.medical_record_number, Participant.last_name
        # The input SPN field is the SCG SPN value.
        SPN: SpecimenCollectionGroup.surgical_pathology_number
        ...
   Use one of the Galena example mapping files as a template.

5. Read the migration script options:
        crtmigrate --help

6. Run the migration script on a test database, e.g.:
        crtmigrate --unique --target TissueSpecimen --mapping fields.yaml input.csv
  The --unique option changes identifying fields, e.g. the protocol name, to a unique value
  for testing purposes.

7. Iterate on the migration until you are satisfied with the result. Drop the --unique option and rerun for a final test.

8. Reconfigure the connection parameters described in the Tissue Configuration [FAQ](/kb/tissue/how-do-i-configure-caruby-to-work-with-catissue) to connect to your production database.
Run the migration on the production server.

9.  If your migration is only partially successful, the --offset option can be used to pick up where you left off.

10. Let us know in a new [Discussion](/discussions) if you have a problem.



