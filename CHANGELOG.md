# Changelog

## v0.6.0

* Bug fixes
  * Fix the `:delay_to_sigkill` option so that it takes milliseconds as
    documented and remove the max delay check. Previously, the code used
    microseconds for the delay despite the documentation. If you were using
    `:delay_to_sigkill`, this is a backwards incompatible change and your delays
    will be 1000x longer. Thanks to Almir for reporting this issue.

## v0.5.1

* New features
  * Added the `:log_prefix` option to MuonTrap.Daemon so that logged output can
    be annotated in more helpful ways. This is useful when running the same
    program multiple times, but with different configurations.

## v0.5.0

This update contains many changes throughout. If you're using cgroups, please
review the changes as they likely affect your code.

* New features
  * Added `:cgroup_base`. The preferred way of using cgroups now is for MuonTrap
    to create a sub-cgroup for running the command. This removes the need to
    keep track of cgroup paths on your own when you run more than one command at
    a time. `:cgroup_path` is still available.
  * Almost all inconsistencies between MuonTrap.Daemon and MuonTrap.cmd/3 have
    been fixed. As a result, MuonTrap.Daemon detects and raises more exceptions
    than previous. It is possible that code that worked before will now break.
  * MuonTrap.Daemon sets its exit status based on the process's exit code.
    Successful exit codes (exit code 0) exit `:normal` and failed exit codes
    (anything else) do not. This makes it possible to use the Supervisor
    `:temporary` restart strategy that only restarts failures.
  * MuonTrap.Daemon supports a `:name` parameter for setting GenServer names.
  * MuonTrap.Daemon `cgget` and `cgset` helpers return ok/error tuples now since
    it was too easy to accidentally call them such that they'd raise.

* Bug fixes
  * Forcefully killed processes would get stuck in a zombie state until the kill
    timeout expired due to a missing call to wait(2). This has been fixed.
  * Exit status of process killed by a signal reflects that. I.e., a process
    killed by a signal exits with a status of 128+signal.

## v0.4.4

* Bug fixes
  * Fixed an issue where environment variable lists passed to MuonTrap.Daemon
    had to be charlists rather than Elixir strings like MuonTrap.cmd/3 and
    System.cmd/3.

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
  * Make MuonTrap.Daemon usable (child_specs, options)

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
