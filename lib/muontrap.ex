# SPDX-FileCopyrightText: 2018 Frank Hunleth
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

  On most Linux distributions, use `cgcreate` to create a new cgroup.  You can
  name them almost anything. The command below creates one named `muontrap` for
  the current user. It supports memory and CPU controls.

  ```sh
  sudo cgcreate -a $(whoami) -g memory,cpu:muontrap
  ```

  Nerves systems do not contain `cgcreate` by default. Due to the simpler Linux
  setup, it may be sufficient to run `File.mkdir_p(cgroup_path)` to create a
  cgroup. For example:

  ```elixir
  File.mkdir_p("/sys/fs/cgroup/memory/muontrap")
  ```

  This creates the cgroup path, `muontrap` under the `memory` controller.  If
  you do not have the `"/sys/fs/cgroup"` directory, you will need to mount it
  or update your `erlinit.config` to mount it for you. See a newer official
  system for an example.
  """

  @doc ~S"""
  Executes a command like `System.cmd/3` via the `muontrap` wrapper.

  ## Options

    * `:cgroup_controllers` - run the command under the specified cgroup controllers. Defaults to `[]`.
    * `:cgroup_base` - create a temporary path under the specified cgroup path
    * `:cgroup_path` - explicitly specify a path to use. Use `:cgroup_base`, unless you must control the path.
    * `:cgroup_sets` - set a cgroup controller parameter before running the command
    * `:delay_to_sigkill` - milliseconds before sending a SIGKILL to a child process if it doesn't exit with a SIGTERM (default 500 ms)
    * `:uid` - run the command using the specified uid or username
    * `:gid` - run the command using the specified gid or group
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

  The next examples only run on Linux. To try this out, create new cgroups:

  ```sh
  sudo cgcreate -a $(whoami) -g memory,cpu:muontrap
  ```

  Run a command, but limit memory so severely that it doesn't work (for demo
  purposes, obviously):

  ```elixir
  iex-donttest> MuonTrap.cmd("echo", ["hello"], cgroup_controllers: ["memory"], cgroup_path: "muontrap/test", cgroup_sets: [{"memory", "memory.limit_in_bytes", "8192"}])
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
