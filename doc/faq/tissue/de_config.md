Annotations are configured caRuby Tissue using the `add_annotation` method. For example, the CaTissue::Participant class defines a new `Clinical` annotation module from the `CA` annotation service with package `clinical_annotation` as follows:
    add_annotation('Clinical', :package => 'clinical_annotation', :service => 'CA')

Custom DEs are configured in the same way. For example, after adding a cognitive score DE to caTissue, configure it in caRuby Tissue as follows:    
    CaTissue::Participant.add_annotation('CognitiveScore', :package => 'cognitive_score', :service => 'CS')