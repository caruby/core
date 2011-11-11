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
    
* Check out a topic branch. All changes are made on a branch rather than the master.
  The master branch is reserved for syncing to other repositories. The topic branch name is
  lower-case with dash separators. A bug fix is prefixed by +fix-+. A new feature is a
  descriptive name without a special prefix. Examples:

        git checkout -b fix-gleason-score         # bug fix
        git checkout -b web-service               # feature

    If the bug is a hotfix to a release, i.e. if the bug might be rolled into a
    patch release, then checkout from the most recent release tag rather than the
    master, e.g.:

        git checkout -b fix-gleason-score v1.5.4

* Make the change on on the branch and add it to git, e.g.:

        git commit -a -- lib/domain/specimen.rb test/lib/catissue/domain/specimen_test.rb
       
  The commit message begins with a capital letter and ends with a period.

* Continue making changes and committing them to your branch. You can interrupt work
  on this branch by switching back and forth between branches e.g.:
  
        git checkout master
        ...
        git checkout fix-gleason-score
        ...

* For a long-lived or co-developed feature branch, periodically push the branch to GitHub
  as needed to save your changes, e.g.:

  git push origin web-service

* If this is a hotfix, then make and test a gem according to the caRuby gem SOP.
  Merge hotfixes into a new release branch, e.g.:

        git checkout -b release-1.5.6 v1.5.5
        git merge fix-gleason-score
        ... # merge other hotfixes
        rake test
        ... # fix regressions and retest as necessary
        git tag v1.5.6
        git push --tags origin release-1.5.6
        gem push caruby-tissue-1.5.6.gem

* When a topic or release branch is ready to be merged into the master, then get the most
  recent version of the server master:

        git pull origin master

* Rebase the master onto the topic or release branch:

        git rebase master

* If there are conflicts, then resolve each conflict and continue the rebase:

        git rebase --continue

* Run the full test suite to confirm that there are no regressions:

        rake test
  
    Fix regressions on the branch and rerun until the full test suite succeeds.
 
* Merge to the master branch, e.g.:

        git checkout master
        git merge --no-ff web-service

    The +--no-ff+ option writes a merge message to the log, even if the merge is a fast-forward merge.
    This log entry helps isolate problems that might subsequently arise from the change. 
  
* Push the changes to GitHub:

        git push origin master
