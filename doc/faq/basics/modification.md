The caRuby source resides in the [git](git-scm.com/) repository on [github](http://github.com/caruby). This source can be modified locally as follows, using `caruby-tissue` modification as an example:

Make changes
--------------------
[Clone](http://crypto.stanford.edu/~blynn/gitmagic/ch03.html) the git repository to a workspace on your local workstation, e.g.
    git clone git://github.com/caruby-tissue/caruby-tissue.git

It is often useful to clone the [caruby-core] repository as well. This is useful for easy reference to the `caruby-core` classes and is necessary if your test case depends on the `caruby-core`  test framework, as is true of `caruby-tissue`.
    git clone git://github.com/caruby-tissue/caruby-core.git

If you plan to submit your changes back to the project,, then make a branch with a descriptive label, e.g.:
    cd catissue
    git checkout -b fix_duplicate_label

Make a test case for your changes. Look in the `test` directory for examples.

Modify the code and test your changes.

Submit your changes
--------------------------
If you wish to submit your changes back to the project, then [make a patch](http://ariejan.net/2009/10/26/how-to-create-and-apply-a-patch-with-git/) to be folded back into the source, e.g.:
    git format-patch master --stdout > caruby-tissue-specimen-patch.diff

Resolve conflicts and [rebase](http://help.github.com/rebase/) your branch, e.g.:
    git checkout master
    git pull
    git checkout fix_duplicate_label
    git rebase master

Attach the patch to a [new discussion](http://caruby.tenderapp.com/discussion/new) that explains what you did.