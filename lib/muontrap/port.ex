# SPDX-FileCopyrightText: 2018 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0

defmodule MuonTrap.Port do
  @moduledoc false

  @spec muontrap_path() :: String.t()
  def muontrap_path() do
    Application.app_dir(:muontrap, ["priv", "muontrap"])
  end

  @doc """
  Run a command in a similar way to System.cmd/3, but taking MuonTrap options

  This code is mostly copy/pasted from System.cmd/3's implementation so that
  it works similarly.
  """
  @spec cmd(MuonTrap.Options.t()) :: {Collectable.t(), exit_status :: non_neg_integer()}
  def cmd(options) do
    opts = [:binary | port_options(options)]
    {initial, fun} = Collectable.into(options.into)

    try do
      do_cmd(Port.open({:spawn_executable, to_charlist(muontrap_path())}, opts), initial, fun)
    catch
      kind, reason ->
        fun.(initial, :halt)
        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      {acc, status} -> {fun.(acc, :done), status}
    end
  end

  defp do_cmd(port, acc, fun) do
    receive do
      {^port, {:data, data}} ->
        report_bytes_handled(port, byte_size(data))
        do_cmd(port, fun.(acc, {:cont, data}), fun)

      {^port, {:exit_status, status}} ->
        {acc, status}
    end
  end

  @spec port_options(MuonTrap.Options.t()) :: list()
  def port_options(options) do
    [
      :use_stdio,
      :exit_status,
      :hide,
      {:args, muontrap_args(options)} | Enum.flat_map(options, &port_option/1)
    ]
  end

  defp muontrap_args(options) do
    Enum.flat_map(options, &muontrap_arg/1) ++ ["--", options.cmd] ++ options.args
  end

  defp muontrap_arg({:cgroup_path, path}), do: ["--group", path]
  defp muontrap_arg({:delay_to_sigkill, delay}), do: ["--delay-to-sigkill", to_string(delay)]
  defp muontrap_arg({:uid, id}), do: ["--uid", to_string(id)]
  defp muontrap_arg({:gid, id}), do: ["--gid", to_string(id)]
  defp muontrap_arg({:arg0, arg0}), do: ["--arg0", arg0]
  defp muontrap_arg({:log_limit, limit}), do: ["--log-limit", to_string(limit)]

  defp muontrap_arg({:cgroup_controllers, controllers}) do
    Enum.flat_map(controllers, fn controller -> ["--controller", controller] end)
  end

  defp muontrap_arg({:cgroup_sets, sets}) do
    Enum.flat_map(sets, fn {controller, variable, value} ->
      ["--controller", controller, "--set", "#{variable}=#{value}"]
    end)
  end

  defp muontrap_arg(_other), do: []

  defp port_option({:stderr_to_stdout, true}), do: [:stderr_to_stdout]
  defp port_option({:env, env}), do: [{:env, env}]

  defp port_option({:cd, bin}), do: [{:cd, bin}]
  defp port_option({:arg0, bin}), do: [{:arg0, bin}]
  defp port_option({:parallelism, bool}), do: [{:parallelism, bool}]
  defp port_option(_other), do: []

  @spec report_bytes_handled(port(), pos_integer()) :: boolean()
  def report_bytes_handled(port, count) when is_port(port) and is_integer(count) do
    cmd = :binary.encode_unsigned(count, :little)
    Port.command(port, cmd)
  rescue
    # A process may attempt to mark the bytes processed after the port has
    # closed but before it received an :exit_status message. In those cases
    # there command will fail with ArgumentError, but should be safe to
    # ignore since we don't need to report anymore
    ArgumentError -> false
  end
end
