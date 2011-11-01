caRuby gem creation procedure
=============================
This SOP describes how a caRuby git commiter publishes a new gem.
The examples refer to a new `caruby-tissue` gem, but the procedure
applies to any caRuby gem.

* Make, test and push your changes to GitHub as described in the `commit` SOP.

* Bump the version number in `lib/catissue/version.rb`.

* Describe the gem theme in `History.md`.

* If the gem dependencies have changed, then update the dependency names and
  version numbers in `caruby-tissue.gemspec`

* Add a version tag with a +v+ prefix, e.g.:

        git tag v1.8.1

* Commit and push the changes with the tag:

        git push --tags

* Make the gem:

        rake gem

* Push the gem

        gem push caruby-tissue-1.8.1.gem

* Periodically clean up unused git topic branches, e.g.:

        gem branch -d save_gleason_score_fix
        
  If the topic branch was saved to the server, then delete that branch as follows:
  
        gem push origin :save_gleason_score_fix

Version numbers
---------------
Versions are numbered according the standard major/minor/patch triplet scheme, adapted as follows:

* Major - Large-scale functional change

* Minor - Addition of a focused feature set

* Patch - Client-compatible bug fixes and refactoring

Each version component starts at 1 rather than 0.

Unstable early adopter releases not intended for general public use are distributed separately as a git
Release Candidate (RC) tag, e.g. `v2RC1`. Likewise, custom branches are tracked as a git fork tag,
e.g. `psbin_v1` for the Prostate Spore BIN fork.

