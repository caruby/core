For Participant `pnt`, create a new alcohol annotation in the database as follows:
    alc = CaTissue::Participant::Clinical::AlcoholHealthAnnotation.new
    alc.drinks_per_week = 4
    alc.participant = pnt
    alc.create

The supported annotation modules include the following:
    Participant::Clinical
    SpecimenCollectionGroup::Pathology
    Specimen::Pathology

Custom DEs added to caTissue are configured as described in the DE configuration [FAQ](/kb/tissue/how-do-i-add-a-custom-dynamic-extension).