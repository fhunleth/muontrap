# Changelog

## v0.4.3

* Bug fixes
  * Reverted removal of `child_spec`

## v0.4.2

* New features
  * MuonTrap.Daemon can log stderr now as well as stdout. Pass
    `stderr_to_stdout: true` in the options. Thanks to Timmo Verlaan for this
    update.

## v0.4.1

* Improvements
  * Move port process build products under `_build`. This fixes an issue where
    changes in MIX_TARGET settings would not be picked up.
  * Improved some specs to remove Dialyzer warnings in some cases

## v0.4.0

* New features
  * MuonTrap.Daemon no longer sends all of the output from the process to the
    logger by default. If you want it logged, pass in a `{:log_output, level}`
    option. This also slightly improves the logged message to make it easier
    to read.

## v0.3.1

* Bug fixes
  * Make MuonTrap.Daemon usable (childspecs, options)

## v0.3.0

* Bug fixes
  * Make MuonTrap.cmd/3 pass the System.cmd/3 tests
  * Add a few more specs and fix Dialyzer errors

## v0.2.2

* Bug fixes
  * Add missing dependency on `:logger`

## v0.2.1

* Bug fixes
  * Fix hex package contents

## v0.2.0

* Bug fixes
  * Fix shutdown timeout and issues with getting EINTR
  * More progress on cgroup testing; docs

## v0.1.0

* Initial release
