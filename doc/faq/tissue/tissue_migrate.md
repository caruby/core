The caRuby Tissue Migrator imports input CSV files into caTissue. The steps to do perform a simple migration are as follows:

1. [Install](http://caruby.tenderapp.com/faq/tissue_install) caruby-tissue.

2. Extract a CSV file from the source tissue repository system.

3. Create a mapping file that associates the input fields with the corresponding caTissue properties, e.g.:
        # The input MRN field is the caTissue PMI MRN and Participant last name.
        MRN: ParticipantMedicalIdentifier.medical_record_number, Participant.last_name
        # The input SPN field is the SCG SPN value.
        SPN: SpecimenCollectionGroup.surgical_pathology_number
        # The input Collection Date is the Specimen received timestamp.
        Collection Date: ReceivedEventParameters.timestamp
        # The input Quantity is the target Specimen initial quantity.
        Quantity: Specimen.initial_quantity

4. Read the migration script options:
        caruby/tissue/bin/catissue-migrate --help

5. Run the migration script, e.g.:
        caruby/tissue/bin/catissue-migrate --target TissueSpecimen --mapping fields.yaml input.csv