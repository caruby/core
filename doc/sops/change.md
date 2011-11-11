caRuby change procedure
===============================
This SOP describes how a caRuby git committer applies source code changes to a caRuby gem.
The examples refer to the `caruby-tissue` gem, but the procedure applies to any caRuby gem.

* Clone the caRuby git repository, if necessary, e.g.:

        cd /path/to/workspace
        git clone git@github.com:caruby/tissue.git

* Update the master tracking branch:

        git branch master
        git pull origin master
    
* Check out a tracking topic branch. All changes are made on a branch rather than the master.
  The master branch is reserved for syncing to other repositories. The topic branch name is
  lower-case with dash separators. A bug fix is prefixed by +fix-+. A new feature is a
  descriptive name without a special prefix.

        git checkout -b fix-gleason-score  # bug fix
        git checkout -b web-service        # feature

* Make the change on on the branch and add it to git, e.g.:

        git commit -a -- lib/domain/specimen.rb test/lib/catissue/domain/specimen_test.rb
       
  The commit message begins with a capital letter and ends with a period.

* Continue making changes and committing them to your branch. You can interrupt work
  on this branch by switching back and forth between branches e.g.:
  
        git checkout master
        ...
        git checkout fix-gleason-score
        ...

* For a long-lived branch, periodically push the branch to GitHub as needed to save your
  changes, e.g.:

        git push origin fix-gleason-score

* When you are ready to merge your changes to the master, then get the most recent
  version of the server master and rebase the tracking branch:

        git pull --rebase origin master

* There will not be a merge conflict unless you applied changes to the master branch
  without pushing the changes to the server. If there are conflicts, then resolve each
  conflict and continue the rebase:

        git rebase --continue

* Run the full test suite to confirm that there are no regressions:

        rake test
  
    Fix regressions on the branch as described above and rerun until the full test suite succeeds.

* Push the completed branch to the server, e.g.:

        git push origin fix-gleason-score
 
* Merge to the master branch:

        git checkout master
        git merge --no-ff fix-gleason-score

    The +--no-ff+ option writes a merge message to the log, even if the merge is a fast-forward merge.
    This log entry is helpful for isolating problems that might subsequently arise from the change. 
  
* Push the changes to GitHub:

        git push

