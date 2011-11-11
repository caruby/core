caRuby bug fix procedure
========================
This SOP describes how a caRuby git committer applies source code changes to fix
a bug. The examples refer to the `caruby-tissue` gem, but the procedure
applies to any caRuby gem.

* Make a topic branch as described in the general caRuby change procedure, e.g.:

        git checkout -b fix-gleason-score v1.5.4 
    
* Isolate the problem to a test case, e.g.:
   
        test/lib/catissue/domain/specimen_test.rb
        def test_save_gleason_score
          ...
        end
  
    The test case should be as focused as possible to reproduce the problem.

* Create a new bug report which describes the problem and references the test case in
  [Lighthouse](caruby.lighthouseapp.com), e.g.:
  
        Prostate specimen annotation Gleason score is not saved when an owner specimen is
        created. Reproduced in specimen_test.rb test_save_gleason_score.

* Document the bug in the test case, e.g.:

        # Verifies the fix to Bug #42 - Prostate specimen annotation Gleason score is not saved.
        def test_save_gleason_score
          ...
        end

* Fix the bug on on the branch and add it to git. The commit message references the bug number, e.g:

        git commit -a -- lib/domain/specimen.rb test/lib/catissue/domain/specimen_test.rb
        Fixed bug #42 - Prostate specimen annotation Gleason score is not saved. Added the
        Gleason score properties as caRuby attributes.
        
* Merge, test and push your changes to GitHub, as described in the general caRuby change procedure.

* If the bug is a hotfix, then roll a new gem as described in the caRuby gem SOP. The 
