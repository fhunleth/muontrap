# Changelog

## v1.5.0

* New feature
  * Add Logger metadata in `MuonTrap.Daemon`. See the `:logger_metadata` option.
    (@bjyoungblood)

## v1.4.1

* Bug fixes
  * Support logging output to all Elixir logger levels. Previously the "new" set
    that includes emergency, critical, warning, etc. would fail the option check
  * Default the `log_transform` option to replace invalid UTF8 characters so
    they don't crash the Logger. This fixes an annoyance where a program would
    do this and there'd be log crash spam. It's still overridable, so users
    using custom loggers that already handle this can pass
    `Function.identity/1` to disable. (@jjcarstens)

## v1.4.0

* New feature
  * Add a timeout option to `MuonTrap.cmd/3`. OS processes that take too long
    will be killed and a `:timeout` return status returned. This is backwards
    compatible. Thanks to @bjyoungblood for adding this feature.

## v1.3.3

* Bug fixes
  * Fix issue where lots of prints from a child process when the Erlang process
    side is killed can cause MuonTrap to not clean up the child process. There
    are some potential variations on this that were also fixed even though they
    were unseen. Thanks to @bjyoungblood for figuring this out.

* Improvements
  * Improve debug logging so that when enabled, fatal errors are written to the
    log as well and not to stderr.

## v1.3.2

* Bug fixes
  * Fix C compiler error when building with older versions of gcc. This fixes an
    compile error with Ubuntu 20.04, for example.

## v1.3.1

* Bug fixes
  * Fix regression where stderr would be printed when `stderr_to_stdout: true`
    was specified and logging disabled.

## v1.3.0

* New feature
  * Add flow control to stdout (and stderr if capturing it) to prevent
    out-of-memory VM crashes from programs that can spam stdout. The output
    would accumulate in the process mailbox waiting to be processed. The flow
    control implementation will push back and slow down output generation. The
    number of bytes in flight defaults to 10 KB and is set with the new
    `:stdio_window` parameter. (@jjcarstens)

* Bug fixes
  * Fix various minor issues preventing unit tests from passing on MacOS.
    (@jjcarstens)

## v1.2.0

* New feature
  * Added `:exit_status_to_reason` to the `Daemon` to be able to change how the
    `Daemon` GenServer exits based on the exit status of the program being run.
    (@erauer)

## v1.1.0

* New features
  * Support transforming output from programs before sending to the log. See the
    new `:log_transform` option. (@brunoro)

## v1.0.0

This release only changes the version number. It has no code changes.

## v0.6.1

This release has no code changes.

* Improvements
  * Clean up build prints, fix a doc typo, and update dependencies for fresher
    docs.

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
