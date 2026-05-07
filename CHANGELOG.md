# Changelog

## v2.0.0

This release drops cgroup v1 support. cgroup v2 (the unified hierarchy) is the
default on every mainstream distribution since 2021–2022, including recent
Nerves systems. If you're stuck on a v1-only host, pin to MuonTrap 1.x.

* Breaking changes
  * cgroup v1 is removed. MuonTrap now requires the v2 unified hierarchy at
    `/sys/fs/cgroup`. Setup uses standard filesystem commands (`mkdir`,
    `chown`) plus enabling controllers in `cgroup.subtree_control` — `cgcreate`
    is no longer needed. See the README for details.
  * `MuonTrap.Daemon.cgget/3` and `cgset/4` lost their `controller` argument
    (it had no meaning under v2). They are now `cgget/2` and `cgset/3`.
  * `MuonTrap.Cgroups.cgget/3` and `cgset/4` similarly lost the `controller`
    argument.
  * The `:cgroup_controllers` and `:cgroup_sets` options are replaced by a
    single `:cgroup` map keyed by atoms like `:memory_max`, `:cpu_weight`,
    `:cpu_max`. Controllers are inferred from the keys; values use Elixir
    types (`:max` atom, `{quota_us, period_us}` tuple for `cpu.max`,
    booleans for flags). Passing the old keys now raises `ArgumentError`.

    ```elixir
    # before
    cgroup_controllers: ["memory", "cpu"],
    cgroup_sets: [
      {"memory", "memory.max", "268435456"},
      {"cpu", "cpu.max", "50000 100000"}
    ]

    # after
    cgroup: %{
      memory_max: 268_435_456,
      cpu_max: {50_000, 100_000}
    }
    ```

    Atom keys correspond to v2 interface files: v1's `memory.limit_in_bytes`
    becomes `:memory_max`; the v1 pair `cpu.cfs_period_us` +
    `cpu.cfs_quota_us` becomes `:cpu_max`; and so on. See `man 7 cgroups`.

* New features
  * `MuonTrap.Daemon.statistics/1` now returns a snapshot of every readable
    cgroup v2 interface file alongside the existing `:output_byte_count`:
    memory usage and peak, OOM-kill counts, parsed `cpu.stat`, PSI
    (`cpu_pressure`, `memory_pressure`, `io_pressure`), `pids.current`,
    `pids.peak`, `cgroup.stat`, and more. Missing files (controller not
    enabled, PSI not compiled in) are silently omitted.
  * `MuonTrap.Daemon.cgroup_config/1` returns the daemon's writable cgroup
    settings as a map keyed by the same atoms accepted by the `:cgroup`
    option, suitable for round-tripping into another daemon.
  * `MuonTrap.Daemon.cgroup_path/1` returns the daemon's cgroup path (or
    `nil` if the daemon isn't running under a cgroup).
  * MuonTrap now uses `cgroup.kill` (kernel 5.14+) for atomic cgroup teardown
    when available, falling back to per-pid SIGKILL on older kernels.
  * Clear startup error if the v2 unified hierarchy is missing.
  * Clear error if a requested controller isn't enabled in the parent's
    `cgroup.subtree_control` (instead of silently running with no limits).

## v1.8.0

* New feature
  * Add `:wait_for` option to `MuonTrap.Daemon`. This lets you specify a
    function that can block until a file, named pipe, local server, etc. is
    available before starting the OS process. This simplifies workarounds for OS
    processes that don't wait or retry on inputs that come up asynchronously.

## v1.7.0

* New feature
  * Add `:capture_stderr_only` option to capture only stderr while ignoring stdout.
    This is useful when you want to capture error messages but not regular output.
    Works with both `MuonTrap.cmd/3` and `MuonTrap.Daemon`. (@fermuch)

## v1.6.1

* Bug fixes
  * Ignore transient EAGAIN, EWOULDBLOCK, and EINTR errors when processing
    acknowledgments from Erlang. These would cause unneeded restarts.
    (@mediremi)

## v1.6.0

* New feature
  * Add `:logger_fun` option to `MuonTrap.Daemon` to allow complete
    customization of the logging process. Pass it a 1-arity function or `mfargs`
    tuple. This option takes precedence over all of the other log related
    options.  (@bjyoungblood)

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
