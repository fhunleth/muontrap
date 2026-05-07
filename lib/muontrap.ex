# SPDX-FileCopyrightText: 2018 Frank Hunleth
# SPDX-FileCopyrightText: 2023 Ben Youngblood
#
# SPDX-License-Identifier: Apache-2.0

defmodule MuonTrap do
  @moduledoc """
  MuonTrap protects you from lost and out of control OS processes.

  You can use it as a `System.cmd/3` replacement or to pull OS processes into
  an Erlang supervision tree via `MuonTrap.Daemon`. Either way, if the Erlang
  process that runs the command dies, then the OS processes will die as well.

  MuonTrap tries very hard to kill OS processes so that remnants don't hang
  around the system when your Erlang code thinks they should be gone. MuonTrap
  can use the Linux kernel's `cgroup` feature to contain the child process and
  all of its children. From there, you can limit CPU and memory and other
  resources to the process group.

  MuonTrap does not require `cgroups` but keep in mind that OS processes can
  escape. It is, however, still an improvement over `System.cmd/3` which does
  not have a mechanism for dealing it OS processes that do not monitor their
  stdin for when to close.

  For more information, see the documentation for `MuonTrap.cmd/3` and
  `MuonTrap.Daemon`

  ## Configuring cgroups

  MuonTrap uses cgroup v2 (the unified hierarchy at `/sys/fs/cgroup`). It does
  not support cgroup v1. v2 is the default on every mainstream distribution
  since 2021–2022 (Ubuntu 22.04+, Debian 11+, RHEL 9+, recent Nerves systems).

  Two pieces of setup are needed at some point before MuonTrap uses a cgroup
  — there's no need to do them at boot, just before the first cgroup-using
  call:

    1. The controllers you want (e.g., `cpu`, `memory`, `pids`) must be
       enabled in the *root* cgroup's `cgroup.subtree_control`. On systemd
       hosts this is managed for you via slices. Otherwise:

       ```sh
       echo +cpu +memory +pids | sudo tee /sys/fs/cgroup/cgroup.subtree_control
       ```

    2. A parent cgroup directory you can write to. MuonTrap creates a
       sub-cgroup underneath it for each spawned process. For example:

       ```sh
       sudo mkdir -p /sys/fs/cgroup/muontrap
       sudo chown -R $(whoami) /sys/fs/cgroup/muontrap
       ```

  On Nerves, where the BEAM runs as root, both steps can run from your
  application's start callback (or any helper module) the first time you
  need cgroups. Pass the parent's name (here, `"muontrap"`) as
  `:cgroup_base`.

  See the project README for worked examples (capping CPU and memory, fork-bomb
  protection, sandboxing with bwrap) and pointers to the kernel cgroup v2 docs.
  """

  @doc ~S"""
  Executes a command like `System.cmd/3` via the `muontrap` wrapper.

  ## Options

    * `:cgroup` - a map of cgroup v2 settings to apply (e.g.
      `%{cpu_weight: 50, memory_max: 500_000_000, pids_max: 256}`). Keys
      mirror the cgroup v2 interface file names with `.` replaced by `_`.
      Controllers are enabled automatically based on which keys are
      present. See `MuonTrap.Daemon.cgroup_config/1` for the supported
      keys and value shapes; pass the map it returns to start a new
      daemon with the same settings.
    * `:cgroup_base` - a parent cgroup under which MuonTrap creates a
      uniquely-named sub-cgroup for this invocation. Prefer this over
      `:cgroup_path`.
    * `:cgroup_path` - use this exact cgroup path instead of letting
      MuonTrap pick one. Make sure nothing else writes to this cgroup,
      since MuonTrap kills every process in it on cleanup.
    * `:delay_to_sigkill` - milliseconds before sending a SIGKILL to a child process if it doesn't exit with a SIGTERM (default 500 ms)
    * `:uid` - run the command using the specified uid or username. When a
      username is given, supplementary groups are loaded from `/etc/group`.
      When a numeric uid is given, supplementary groups inherit from the
      parent. See `:groups` to override.
    * `:gid` - run the command using the specified gid or group
    * `:groups` - explicit list of supplementary group ids or names (as
      integers or binaries). Pass `[]` to drop all supplementary groups.
      Overrides the supplementary-group behavior described under `:uid`.
    * `:timeout` - milliseconds to wait for the command to complete. If the
      command does not exit before the timeout, the return value will contain
      the output up to that point and `:timeout` as the exit status. The child
      process will be sent SIGTERM

  The following `System.cmd/3` options are also available:

    * `:into` - injects the result into the given collectable, defaults to `""`
    * `:cd` - the directory to run the command in
    * `:env` - an enumerable of tuples containing environment key-value as binary
    * `:arg0` - sets the command arg0
    * `:stderr_to_stdout` - redirects stderr to stdout when `true`
    * `:capture_stderr_only` - when `true`, captures only stderr and ignores stdout (useful for capturing errors while ignoring normal output)
    * `:parallelism` - when `true`, the VM will schedule port tasks to improve
      parallelism in the system. If set to `false`, the VM will try to perform
      commands immediately, improving latency at the expense of parallelism.
      The default can be set on system startup by passing the "+spp" argument
      to `--erl`.

  ## Examples

  Run a command:

  ```elixir
  iex> MuonTrap.cmd("echo", ["hello"])
  {"hello\n", 0}
  ```

  The next examples only run on Linux. To try this out, create a parent
  cgroup and ensure cpu/memory are enabled in the root subtree (see the
  `Configuring cgroups` section above):

  ```sh
  sudo mkdir -p /sys/fs/cgroup/muontrap
  sudo chown -R $(whoami) /sys/fs/cgroup/muontrap
  ```

  Run a command, but limit memory so severely that it can't allocate (for
  demo purposes, obviously):

  ```elixir
  iex-donttest> MuonTrap.cmd("echo", ["hello"], cgroup_path: "muontrap/test", cgroup: %{memory_max: 1_048_576})
  {"", 1}
  ```

  Run a command with a timeout:

  iex> MuonTrap.cmd("/bin/sh", ["-c", "echo start && sleep 10 && echo end"], timeout: 100)
  {"start\n", :timeout}
  """
  @spec cmd(binary(), [binary()], keyword()) ::
          {Collectable.t(), exit_status :: non_neg_integer() | :timeout}
  def cmd(command, args, opts \\ []) when is_binary(command) and is_list(args) do
    options = MuonTrap.Options.validate(:cmd, command, args, opts)

    MuonTrap.Port.cmd(options)
  end

  @doc """
  Return the absolute path to the muontrap executable.

  Call this if you want to invoke the `muontrap` port binary manually.
  """
  defdelegate muontrap_path, to: MuonTrap.Port
end
