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

  alias MuonTrap.Options

  @doc ~S"""
  Executes a command like `System.cmd/3` via the `muontrap` wrapper.

  # Options

    * `:cgroup_controllers` - run the command under the specified cgroup controllers. Defaults to `[]`.
    * `:cgroup_path` - use the specified path for the cgroup
    * `:cgroup_sets` - set a cgroup controller parameter before running the command
    * `:delay_to_sigkill` - milliseconds before sending a SIGKILL to a child process if it doesn't exit with a SIGTERM
    * `:uid` - run the command using the specified uid or username
    * `:gid` - run the command using the specified gid or group

  See `System.cmd/3` for additional options.

  # Examples

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
  """
  @spec cmd(binary(), [binary()], keyword()) ::
          {Collectable.t(), exit_status :: non_neg_integer()}
  def cmd(command, args, opts \\ []) when is_binary(command) and is_list(args) do
    assert_no_null_byte!(command, "MuonTrap.cmd/3")

    unless Enum.all?(args, &is_binary/1) do
      raise ArgumentError, "all arguments for MuonTrap.cmd/3 must be binaries"
    end

    command = System.find_executable(command) || :erlang.error(:enoent, [command, args, opts])

    {muontrap_args, updated_opts} = Options.to_args(opts)
    updated_args = muontrap_args ++ ["--", command] ++ args
    System.cmd(muontrap_path(), updated_args, updated_opts)
  end

  @doc """
  Return the absolute path to the muontrap executable.

  Call this if you want to invoke the `muontrap` port binary manually.
  """
  @spec muontrap_path() :: binary()
  def muontrap_path() do
    Application.app_dir(:muontrap, "priv/muontrap")
  end

  # Copied from Elixir's system.ex to make MuonTrap.cmd pass System.cmd's tests
  defp assert_no_null_byte!(binary, operation) do
    case :binary.match(binary, "\0") do
      {_, _} ->
        raise ArgumentError,
              "cannot execute #{operation} for program with null byte, got: #{inspect(binary)}"

      :nomatch ->
        :ok
    end
  end
end
