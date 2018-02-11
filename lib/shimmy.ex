defmodule Shimmy do
  @moduledoc """
  Documentation for Shimmy.
  """

  @doc """
  Executes a command like `System.cmd/3` but using `shimmy`.

  ## Examples

      iex> Shimmy.cmd("echo", ["hello"])
      {"hello\n", 0}

  ## Options

    * :cgroup_controller - run the command under the specified cgroup controllers. Defaults to [].
    * :cgroup_path - use the specified path for the cgroup
    * :cgroup_set - set a cgroup controller parameter before running the command
    * :delay_to_sigkill - milliseconds before sending a SIGKILL to a child process if it doesn't exit with a SIGTERM
    * :uid - run the command using the specified uid or username
    * :gid - run the command using the specified gid or group

    See `System.cmd` for additional options.

     {"controller", required_argument, 0, 'c'},
    {"help",     no_argument,       0, 'h'},
    {"delay-to-sigkill", required_argument, 0, 'k'},
    {"path", required_argument, 0, 'p'},
    {"set", required_argument, 0, 's'},
    {"uid", required_argument, 0, 'u'},
    {"gid", required_argument, 0, 'g'},

  """
  @spec cmd(binary(), [binary()], keyword()) :: {Collectable.t(), exit_status :: non_neg_integer()}
  def cmd(command, args, opts \\ []) do
    {shimmy_args, updated_opts} = options_to_args(opts, [], [])
    updated_args = shimmy_args ++ ["--", command] ++ args
    System.cmd(shimmy_path(), updated_args, updated_opts)
  end

  defp options_to_args([], args, opts), do: {args, opts}
  defp options_to_args([{:cgroup_controller, controllers} | rest], args, opts) do
    new_args = controllers_to_args(controllers, [])
    options_to_args(rest, new_args ++ args, opts)
  end
  defp options_to_args([{:cgroup_path, path} | rest], args, opts) do
    options_to_args(rest, ["--path", path | args], opts)
  end
  defp options_to_args([{:delay_to_sigkill, delay} | rest], args, opts) do
    options_to_args(rest, ["--delay-to-sigkill", "#{delay}" | args], opts)
  end
  defp options_to_args([{:cgroup_set, sets} | rest], args, opts) do
    new_args = sets_to_args(sets, [])
    options_to_args(rest, new_args ++ args, opts)
  end
  defp options_to_args([{:uid, uid} | rest], args, opts) do
    options_to_args(rest, ["--uid", "#{uid}" | args], opts)
  end
  defp options_to_args([{:gid, gid} | rest], args, opts) do
    options_to_args(rest, ["--gid", "#{gid}" | args], opts)
  end
  defp options_to_args([other | rest], args, opts) do
    options_to_args(rest, args, [other | opts])
  end

  defp controllers_to_args([], args), do: args
  defp controllers_to_args([controller | rest], args) do
    new_args = ["--controller", controller | args]
    controllers_to_args(rest, new_args)
  end

  defp sets_to_args([], args), do: args
  defp sets_to_args([controller | rest], args) do
    new_args = ["--set", controller | args]
    controllers_to_args(rest, new_args)
  end

  defp shimmy_path() do
    Application.app_dir(:shimmy, "priv/shimmy")
  end
end
