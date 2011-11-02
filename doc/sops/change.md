caRuby commiter change procedure
================================
This SOP describes how a caRuby git commiter applies source code changes.
The examples refer to fixing a bug in the `caruby-tissue` gem, but the procedure
applies to any caRuby gem.

* Clone the caRuby git repository, if necessary, e.g.:

        cd /path/to/workspace
        git clone git@github.com:caruby/tissue.git

* Update the master tracking branch:

        git branch master
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

* Check out a tracking topic branch. All changes are made on a branch rather than the master.
  The master branch is reserved for syncing to other repositories.

        git checkout -b save_gleason_score_fix

* Fix the bug on on the branch and add it to git, e.g.:

        git commit -a -- lib/domain/specimen.rb test/lib/catissue/domain/specimen_test.rb
        Fixed bug #42 - Prostate specimen annotation Gleason score is not saved. Added the
        Gleason score properties as caRuby attributes.
        
  The commit message begins with a capital letter and end with a period.

* Continue making changes and committing them to your branch. You can interrupt work
  on this branch by switching back and forth between branches e.g.:
  
        git checkout master
        ...
        git checkout save_gleason_score_fix
        ...

* For a long-lived branch, periodically push the branch to GitHub as needed to save your
  changes, e.g.:

        git push origin save_gleason_score_fix

* When you are ready to merge your changes to the master, then get the most recent
  version of the server master, rebase the tracking branch and run the full test script
  to confirm that there are no regressions:

        git pull --rebase origin master
        rake test
    
* If there are rebase conflicts, then fix the conflicts and continue the rebase:

        git rebase --continue

* Push the completed branch to the server, e.g.:

        git push origin save_gleason_score_fix
 
* Perform a fast-forward merge to the master branch:

        git checkout master
        git merge save_gleason_score_fix

* Push the changes to GitHub:

        git push origin master

