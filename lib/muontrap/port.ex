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
  @spec cmd(MuonTrap.Options.t()) ::
          {Collectable.t(), exit_status :: non_neg_integer() | :timeout}
  def cmd(options) do
    opts = port_options(options, ["--capture-output"])
    {initial, fun} = Collectable.into(options.into)
    {maybe_timer, timeout_message} = maybe_start_timer(options[:timeout])

    try do
      port = Port.open({:spawn_executable, to_charlist(muontrap_path())}, opts)
      do_cmd(port, initial, fun, timeout_message)
    catch
      kind, reason ->
        fun.(initial, :halt)
        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      {acc, status} -> {fun.(acc, :done), status}
    after
      maybe_stop_timer(maybe_timer, timeout_message)
    end
  end

  defp do_cmd(port, acc, fun, timeout_message) do
    receive do
      {^port, {:data, data}} ->
        report_bytes_handled(port, byte_size(data))
        do_cmd(port, fun.(acc, {:cont, data}), fun, timeout_message)

      {^port, {:exit_status, status}} ->
        {acc, status}

      ^timeout_message ->
        Port.close(port)
        {acc, :timeout}
    end
  end

  @spec port_options(MuonTrap.Options.t(), [String.t()]) :: list()
  def port_options(options, args \\ []) do
    [
      :use_stdio,
      :exit_status,
      :binary,
      :hide,
      {:args, args ++ muontrap_args(options)} | Enum.flat_map(options, &port_option/1)
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
  defp muontrap_arg({:stdio_window, count}), do: ["--stdio-window", to_string(count)]
  defp muontrap_arg({:stderr_to_stdout, true}), do: ["--capture-stderr"]
  defp muontrap_arg({:log_output, _}), do: ["--capture-output"]

  defp muontrap_arg({:cgroup_controllers, controllers}) do
    Enum.flat_map(controllers, fn controller -> ["--controller", controller] end)
  end

  defp muontrap_arg({:cgroup_sets, sets}) do
    Enum.flat_map(sets, fn {controller, variable, value} ->
      ["--controller", controller, "--set", "#{variable}=#{value}"]
    end)
  end

  defp muontrap_arg(_other), do: []

  defp port_option({:env, env}), do: [{:env, env}]
  defp port_option({:cd, bin}), do: [{:cd, bin}]
  defp port_option({:arg0, bin}), do: [{:arg0, bin}]
  defp port_option({:parallelism, bool}), do: [{:parallelism, bool}]
  defp port_option(_other), do: []

  @spec report_bytes_handled(port(), pos_integer()) :: :ok
  def report_bytes_handled(port, count) when is_port(port) and is_integer(count) do
    cmd = encode_acks(count)
    _ = Port.command(port, cmd)
    :ok
  rescue
    # A process may attempt to mark the bytes processed after the port has
    # closed but before it received an :exit_status message. In those cases
    # the command will fail with ArgumentError, but should be safe to
    # ignore since we don't need to report anymore
    ArgumentError -> :ok
  end

  # Each acknowledgment is one unsigned byte that's the number of bytes to acknowledge
  # plus 1. E.g., 0 means to acknowledge 1 byte. 255 means to acknowledge 256 bytes.
  @spec encode_acks(pos_integer()) :: iodata()
  def encode_acks(count) when count > 0 do
    full_acks = div(count, 256)
    partial_acks = rem(count, 256)
    encode_acks_helper(full_acks, partial_acks)
  end

  defp encode_acks_helper(0, partial_acks), do: <<partial_acks - 1>>
  defp encode_acks_helper(full_acks, 0), do: :binary.copy(<<255>>, full_acks)

  defp encode_acks_helper(full_acks, partial_acks),
    do: [:binary.copy(<<255>>, full_acks), partial_acks - 1]

  @spec maybe_start_timer(non_neg_integer() | nil) :: {reference() | nil, {:timeout, reference()}}
  defp maybe_start_timer(timeout) when is_integer(timeout) do
    timeout_message = {:timeout, make_ref()}
    timer_ref = Process.send_after(self(), timeout_message, timeout)
    {timer_ref, timeout_message}
  end

  # When not setting a timer, return a fake message. This simplifies pattern
  # matching in cmd/1 and do_cmd/4.
  defp maybe_start_timer(_), do: {nil, {:timeout, make_ref()}}

  @spec maybe_stop_timer(reference() | nil, {:timeout, reference()}) :: :ok
  defp maybe_stop_timer(nil, _), do: :ok

  defp maybe_stop_timer(timer_ref, timeout_message) do
    # Ensure we capture the timeout message in case it arrives around the same
    # time the command completes.
    if Process.cancel_timer(timer_ref) == false do
      receive do
        ^timeout_message -> :ok
      after
        0 -> :ok
      end
    end

    :ok
  end
end
