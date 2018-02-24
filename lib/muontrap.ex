defmodule MuonTrap do
  @moduledoc """
  Documentation for MuonTrap.
  """
  alias MuonTrap.Options

  @doc ~S"""
  Executes a command like `System.cmd/3` but using `muontrap`.

  ## Examples

      iex> MuonTrap.cmd("echo", ["hello"])
      {"hello\n", 0}

  ## Options

    * :cgroup_controllers - run the command under the specified cgroup controllers. Defaults to [].
    * :cgroup_path - use the specified path for the cgroup
    * :cgroup_sets - set a cgroup controller parameter before running the command
    * :delay_to_sigkill - milliseconds before sending a SIGKILL to a child process if it doesn't exit with a SIGTERM
    * :uid - run the command using the specified uid or username
    * :gid - run the command using the specified gid or group

    See `System.cmd` for additional options.
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
  """
  def muontrap_path() do
    Application.app_dir(:muontrap, "priv/muontrap")
  end
end
