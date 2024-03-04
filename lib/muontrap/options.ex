# SPDX-FileCopyrightText: 2018 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0

defmodule MuonTrap.Options do
  @moduledoc """
  Validate and normalize the options passed to MuonTrap.cmd/3 and MuonTrap.Daemon.start_link/3

  This module is generally not called directly, but it's likely
  the source of exceptions if any options aren't quite right. Call `validate/4` directly to
  debug or check options without invoking a command.
  """

  @typedoc """
  The following fields are always present:

  * `:cmd` - the command to run
  * `:args` - a list of arguments to the command

  The next fields are optional:

  * `:into` - `MuonTrap.cmd/3` only
  * `:cd`
  * `:arg0`
  * `:stderr_to_stdout`
  * `:parallelism`
  * `:env`
  * `:name` - `MuonTrap.Daemon`-only
  * `:log_output` - `MuonTrap.Daemon`-only
  * `:log_prefix` - `MuonTrap.Daemon`-only
  * `:log_transform` - `MuonTrap.Daemon`-only
  * `:logger_metadata` - `MuonTrap.Daemon`-only
  * `:stdio_window`
  * `:exit_status_to_reason` - `MuonTrap.Daemon`-only
  * `:cgroup_controllers`
  * `:cgroup_path`
  * `:cgroup_base`
  * `:delay_to_sigkill`
  * `:cgroup_sets`
  * `:uid`
  * `:gid`
  * `:timeout` - `MuonTrap.cmd/3` only

  """
  @type t() :: map()

  # See https://hexdocs.pm/logger/Logger.html#module-levels
  # Include `:warn` for older Elixir versions
  @log_levels [:emergency, :alert, :critical, :error, :warning, :warn, :notice, :info, :debug]

  @doc """
  Validate options and normalize them for invoking commands

  Pass in `:cmd` or `:daemon` for the first parameter to allow function-specific
  options.
  """
  @spec validate(:cmd | :daemon, binary(), [binary()], keyword()) :: t()
  def validate(context, cmd, args, opts) when context in [:cmd, :daemon] do
    assert_no_null_byte!(cmd, context)

    unless Enum.all?(args, &is_binary/1) do
      raise ArgumentError, "all arguments for #{operation(context)} must be binaries"
    end

    abs_command = System.find_executable(cmd) || :erlang.error(:enoent, [cmd, args, opts])

    validate_options(context, abs_command, args, opts)
    |> resolve_cgroup_path()
  end

  defp resolve_cgroup_path(%{cgroup_path: _path, cgroup_base: _base}) do
    raise ArgumentError, "cannot specify both a cgroup_path and a cgroup_base"
  end

  defp resolve_cgroup_path(%{cgroup_base: base} = options) do
    # Create a random subfolder for this invocation
    Map.put(options, :cgroup_path, Path.join(base, random_string()))
  end

  defp resolve_cgroup_path(other), do: other

  # Thanks https://github.com/danhper/elixir-temp/blob/master/lib/temp.ex
  defp random_string() do
    Integer.to_string(:rand.uniform(0x100000000), 36) |> String.downcase()
  end

  defp validate_options(context, cmd, args, opts) do
    Enum.reduce(
      opts,
      %{cmd: cmd, args: args, into: ""},
      &validate_option(context, &1, &2)
    )
  end

  # System.cmd/3 options
  defp validate_option(:cmd, {:into, what}, opts), do: Map.put(opts, :into, what)
  defp validate_option(_any, {:cd, bin}, opts) when is_binary(bin), do: Map.put(opts, :cd, bin)

  defp validate_option(_any, {:arg0, bin}, opts) when is_binary(bin),
    do: Map.put(opts, :arg0, bin)

  defp validate_option(_any, {:stderr_to_stdout, bool}, opts) when is_boolean(bool),
    do: Map.put(opts, :stderr_to_stdout, bool)

  defp validate_option(_any, {:parallelism, bool}, opts) when is_boolean(bool),
    do: Map.put(opts, :parallelism, bool)

  defp validate_option(_any, {:env, enum}, opts),
    do: Map.put(opts, :env, validate_env(enum))

  # MuonTrap.Daemon options
  defp validate_option(:daemon, {:name, name}, opts),
    do: Map.put(opts, :name, name)

  defp validate_option(:daemon, {:log_output, level}, opts) when level in @log_levels,
    do: Map.put(opts, :log_output, level)

  defp validate_option(:daemon, {:log_prefix, prefix}, opts) when is_binary(prefix),
    do: Map.put(opts, :log_prefix, prefix)

  defp validate_option(:daemon, {:log_transform, log_transform}, opts)
       when is_function(log_transform),
       do: Map.put(opts, :log_transform, log_transform)

  defp validate_option(:daemon, {:logger_metadata, metadata}, opts) when is_list(metadata),
    do: Map.put(opts, :logger_metadata, metadata)

  defp validate_option(_any, {:stdio_window, count}, opts) when is_integer(count),
    do: Map.put(opts, :stdio_window, count)

  defp validate_option(:daemon, {:exit_status_to_reason, exit_status_to_reason}, opts)
       when is_function(exit_status_to_reason),
       do: Map.put(opts, :exit_status_to_reason, exit_status_to_reason)

  # MuonTrap common options
  defp validate_option(_any, {:cgroup_controllers, controllers}, opts) when is_list(controllers),
    do: Map.put(opts, :cgroup_controllers, controllers)

  defp validate_option(_any, {:cgroup_path, path}, opts) when is_binary(path) do
    Map.put(opts, :cgroup_path, path)
  end

  defp validate_option(_any, {:cgroup_base, path}, opts) when is_binary(path) do
    Map.put(opts, :cgroup_base, path)
  end

  defp validate_option(_any, {:delay_to_sigkill, delay}, opts) when is_integer(delay),
    do: Map.put(opts, :delay_to_sigkill, delay)

  defp validate_option(_any, {:cgroup_sets, sets}, opts) when is_list(sets),
    do: Map.put(opts, :cgroup_sets, sets)

  defp validate_option(_any, {:uid, id}, opts) when is_integer(id) or is_binary(id),
    do: Map.put(opts, :uid, id)

  defp validate_option(_any, {:gid, id}, opts) when is_integer(id) or is_binary(id),
    do: Map.put(opts, :gid, id)

  defp validate_option(:cmd, {:timeout, timeout}, opts) when is_integer(timeout) and timeout > 0,
    do: Map.put(opts, :timeout, timeout)

  defp validate_option(_any, {key, val}, _opts),
    do: raise(ArgumentError, "invalid option #{inspect(key)} with value #{inspect(val)}")

  defp validate_env(enum) do
    Enum.map(enum, fn
      {k, nil} ->
        {String.to_charlist(k), false}

      {k, v} ->
        {String.to_charlist(k), String.to_charlist(v)}

      other ->
        raise ArgumentError, "invalid environment key-value #{inspect(other)}"
    end)
  end

  # Copied from Elixir's system.ex to make MuonTrap.cmd pass System.cmd's tests
  defp assert_no_null_byte!(binary, context) do
    case :binary.match(binary, "\0") do
      {_, _} ->
        raise ArgumentError,
              "cannot execute #{operation(context)} for program with null byte, got: #{inspect(binary)}"

      :nomatch ->
        :ok
    end
  end

  defp operation(:cmd), do: "MuonTrap.cmd/3"
  defp operation(:daemon), do: "MuonTrap.Daemon.start_link/3"
end
