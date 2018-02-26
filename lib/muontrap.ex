defmodule MuonTrap do
  @moduledoc """
  MuonTrap protects you from lost and out of control processes.
  """

  alias MuonTrap.Options

  @doc ~S"""
  Executes a command like `System.cmd/3` via the `muontrap` wrapper.

  # Options

    * :cgroup_controllers - run the command under the specified cgroup controllers. Defaults to [].
    * :cgroup_path - use the specified path for the cgroup
    * :cgroup_sets - set a cgroup controller parameter before running the command
    * :delay_to_sigkill - milliseconds before sending a SIGKILL to a child process if it doesn't exit with a SIGTERM
    * :uid - run the command using the specified uid or username
    * :gid - run the command using the specified gid or group

  See `System.cmd/3` for additional options.

  # Examples

  Run a command:

     iex> MuonTrap.cmd("echo", ["hello"])
     {"hello\n", 0}

  The next examples only run on Linux. To try this out, create new cgroups:

     $ sudo cgcreate -a $(whoami) -g memory,cpu:muontrap

  Run a command, but limit memory so severely that it doesn't work (for demo
  purposes, obviously):

     iex-donttest> MuonTrap.cmd("echo", ["hello"], cgroup_controllers: ["memory"], cgroup_path: "muontrap/test", cgroup_sets: [{"memory", "memory.limit_in_bytes", "8192"}])
     {"", 1}
 """
  @spec cmd(binary(), [binary()], keyword()) ::
          {Collectable.t(), exit_status :: non_neg_integer()}
  def cmd(command, args, opts \\ []) do
    {muontrap_args, updated_opts} = Options.to_args(opts)
    updated_args = muontrap_args ++ ["--", command] ++ args
    System.cmd(muontrap_path(), updated_args, updated_opts)
  end

  @doc """
  Return the absolute path to the muontrap executable.

  Call this if you want to invoke the `muontrap` port binary manually.
  """
  def muontrap_path() do
    Application.app_dir(:muontrap, "priv/muontrap")
  end
end
