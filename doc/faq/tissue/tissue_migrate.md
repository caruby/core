The caRuby Tissue Migrator imports input CSV files into caTissue. A migration is performed as follows:

1. [Install](/kb/getting-started/how-do-i-install-caruby) caRuby Tissue.

2. Peruse the caRuby Galena migration [example](https://github.com/caruby/tissue/blob/master/examples/galena/README.md).

3. Enter the following to locate the example installed on your workstation:

        crtexample

4. Copy the example to a location of your choosing. Use this example as a starting point for your own migration.

5. Try some example migrations into your test caTissue database.

6. Extract your own source tissue inventory system CSV file.

7. Create the mapping file that associates your input fields with the corresponding caTissue properties, e.g.:
        # The input MRN field is the caTissue PMI MRN and Participant last name.
        MRN: ParticipantMedicalIdentifier.medical_record_number, Participant.last_name
        # The input SPN field is the SCG SPN value.
        SPN: SpecimenCollectionGroup.surgical_pathology_number
        ...
   Use one of the Galena example mapping files as a template.

8. Read the migration script options:
        crtmigrate --help

9. Run the migration script on a test database, e.g.:
        crtmigrate --unique --target TissueSpecimen --mapping fields.yaml input.csv
  The --unique option changes identifying fields, e.g. the protocol name, to a unique value
  for testing purposes.

10. Iterate on the migration until you are satisfied with the result. Drop the --unique option and rerun for a final test.

11. Reconfigure the connection parameters described in the Tissue Configuration [FAQ](/kb/tissue/how-do-i-configure-caruby-to-work-with-catissue) to connect to your production database.
Run the migration on the production server.

12.  If your migration is only partially successful, the --offset option can be used to pick up where you left off.

13. Let us know in a new [Discussion](/discussions) if you have a problem.