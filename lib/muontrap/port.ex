defmodule MuonTrap.Port do
  @moduledoc false

  @force_port_close -11

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
    opts = port_options(options)
    {initial, fun} = Collectable.into(options.into)

    try do
      port = Port.open({:spawn_executable, to_charlist(muontrap_path())}, opts)
      if force_close_port?(options), do: send_port_close_after(port, Map.get(options, :force_close_port_after))
      do_cmd(port, initial, fun)
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
      {:force_close_port_after, port} ->
        # Port.info/1 will return `nil` if the port is already closed
        unless Port.info(port) == nil, do: Port.close(port)
        {"", @force_port_close}
      {^port, {:data, data}} ->
        do_cmd(port, fun.(acc, {:cont, data}), fun)

      {^port, {:exit_status, status}} ->
        {acc, status}
    end
  end

  def port_options(options) do
    [
      :use_stdio,
      :exit_status,
      :binary,
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

  defp force_close_port?(%{force_close_port_after: delay}) when is_integer(delay), do: true
  defp force_close_port?(_), do: false

  defp send_port_close_after(port, delay) do
    Process.send_after(self(), {:force_close_port_after, port}, delay)
  end
end
