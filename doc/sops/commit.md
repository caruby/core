caRuby commiter change procedure
================================
This SOP describes how a caRuby git commiter applies source code changes.
The examples refer to fixing a bug in the `caruby-tissue` gem, but the procedure
applies to any caRuby gem.

* Clone the caRuby git repository, if necessary, e.g.:

        cd /path/to/workspace
        git clone git@github.com:caruby/tissue.git

* Update the master tracking branch, if necessary:

        git pull
    
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

* Check out a branch:

        git checkout -b save_gleason_score_fix origin/master

* Fix the bug on on the branch, e.g.:

        git commit -a -- lib/domain/specimen.rb test/lib/catissue/domain/specimen_test.rb
        Fixed bug #42 - Prostate specimen annotation Gleason score is not saved. Added the
        Gleason score properties as caRuby attributes.
        
  Commit messages begin with a capital letter and end with a period.

* Run the full test script and confirm that there are no regressions:

        rake test

* Push the branch to GitHub, e.g.:

        git push origin save_gleason_score_fix

* Rebase the tracking branch:

        git rebase origin
    
* If there are conflicts, then fix the conflicts and continue the rebase:

        git rebase --continue

* Perform a fast-forward merge to the master branch:

        git branch master
        git merge save_gleason_score_fix

* Push the change to GitHub:

        git push
