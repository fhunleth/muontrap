# SPDX-FileCopyrightText: 2018 Frank Hunleth
# SPDX-FileCopyrightText: 2018 Matt Ludwigs
# SPDX-FileCopyrightText: 2021 Aldebaran Alonso
# SPDX-FileCopyrightText: 2023 Eric Rauer
# SPDX-FileCopyrightText: 2023 Jon Carstens
# SPDX-FileCopyrightText: 2024 Ben Youngblood
# SPDX-FileCopyrightText: 2024 Milan Vit
# SPDX-FileCopyrightText: 2025 Fernando Mumbach
#
# SPDX-License-Identifier: Apache-2.0

defmodule MuonTrap.Daemon do
  @moduledoc """
  Wrap an OS process in a GenServer so that it can be supervised.

  For example, in your children list add MuonTrap.Daemon like this:

  ```elixir
  children = [
    {MuonTrap.Daemon, ["my_server", ["--options", "foo"], [cd: "/some_directory"]]}
  ]

  opts = [strategy: :one_for_one, name: MyApplication.Supervisor]
  Supervisor.start_link(children, opts)
  ```

  In the `child_spec` tuple, the second element is a list that corresponds to
  the `MuonTrap.cmd/3` parameters. I.e., The first item in the list is the
  program to run, the second is a list of commandline arguments, and the third
  is a list of options. The same options as `MuonTrap.cmd/3` are available with
  the following additions:

  * `:name` - Name the Daemon GenServer
  * `:logger_fun` - Pass a 1-arity function or `t:mfargs/0` tuple to replace
    the default logging behavior. When set, `:log_output`, `:log_prefix`,
    `:log_transform`,
    and `:logger_metadata` will be ignored.
  * `:log_output` - When set, send output from the command to the Logger.
    Specify the log level (e.g., `:debug`)
  * `:log_prefix` - Prefix each log message with this string (defaults to the
    program's path)
  * `:log_transform` - Pass a function that takes a string and returns a string
    to format output from the command. Defaults to `String.replace_invalid/1`
    on Elixir 1.16+ to avoid crashing the logger on non-UTF8 output.
  * `:logger_metadata` - A keyword list to merge into the process's logger metadata.
    The `:muontrap_cmd` and `:muontrap_args` keys are automatically added and
    cannot be overridden.
  * `:stderr_to_stdout` - When set to `true`, redirect stderr to stdout.
    Defaults to `false`.
  * `:capture_stderr_only` - When set to `true`, capture only stderr and ignore stdout.
    This is useful when you want to capture error messages but not regular output.
    Defaults to `false`.
  * `:exit_status_to_reason` - Optional function to convert the exit status (a
    number) to stop reason for the Daemon GenServer. Use if error exit codes
    carry information or aren't errors.
  * `:wait_for` - A 0-arity function that runs before the OS process is
    launched. Use to wait for a required resource to be available. The return
    value is ignored. Raise to abort the launch.

  If you want to run multiple `MuonTrap.Daemon`s under one supervisor, they'll
  all need unique IDs. Use `Supervisor.child_spec/2` like this:

  ```elixir
  Supervisor.child_spec({MuonTrap.Daemon, ["my_server", []]}, id: :server1)
  ```
  """
  use GenServer

  alias MuonTrap.Cgroups

  require Logger

  defstruct [
    :buffer,
    :command,
    :port,
    :port_options,
    :cgroup_path,
    :logger_fun,
    :exit_status_to_reason,
    :output_byte_count,
    :wait_task
  ]

  @max_data_to_buffer 256

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec([command, args]) do
    child_spec([command, args, []])
  end

  def child_spec([command, args, opts]) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [command, args, opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @doc """
  Start/link a deamon GenServer for the specified command.
  """
  @spec start_link(binary(), [binary()], keyword()) :: GenServer.on_start()
  def start_link(command, args, opts \\ []) do
    {genserver_opts, opts} =
      case Keyword.pop(opts, :name) do
        {nil, _opts} -> {[], opts}
        {name, new_opts} -> {[name: name], new_opts}
      end

    GenServer.start_link(__MODULE__, [command, args, opts], genserver_opts)
  end

  @doc """
  Read a cgroup v2 interface file from the daemon's cgroup.

  `variable_name` is a v2 interface file like `"memory.current"` or
  `"cpu.stat"`. See `man 7 cgroups` and the kernel's
  `Documentation/admin-guide/cgroup-v2.rst` for the full list.

  Returns `{:error, :no_cgroup}` if the daemon wasn't started under a
  cgroup.
  """
  @spec cgget(GenServer.server(), binary()) ::
          {:ok, String.t()} | {:error, File.posix() | :no_cgroup}
  def cgget(server, variable_name) do
    GenServer.call(server, {:cgget, variable_name})
  end

  @doc """
  Write a value to a cgroup v2 interface file in the daemon's cgroup.

  Returns `{:error, :no_cgroup}` if the daemon wasn't started under a
  cgroup.
  """
  @spec cgset(GenServer.server(), binary(), binary()) ::
          :ok | {:error, File.posix() | :no_cgroup}
  def cgset(server, variable_name, value) do
    GenServer.call(server, {:cgset, variable_name, value})
  end

  @doc """
  Return the daemon's writable cgroup settings as a flat map.

  Keys mirror the cgroup v2 interface file names with `.` replaced by
  `_` (e.g. `cpu.weight` → `:cpu_weight`, `memory.swap.max` →
  `:memory_swap_max`). Files that aren't present (controller not
  enabled, knob not in this kernel) are omitted. Returns an empty map
  if the daemon isn't running under a cgroup.

  The returned map is accepted as the `:cgroup` option on
  `start_link/3`/`MuonTrap.cmd/3`, so you can read one daemon's
  settings and start another with the same configuration under a fresh
  `cgroup_path` (or `cgroup_base`).

  Possible keys:

  * `:cpu_weight` - integer 1..10000 (default 100)
  * `:cpu_max` - `:max` or `{quota_us, period_us}`
  * `:cpu_idle` - boolean
  * `:memory_min`, `:memory_low` - bytes
  * `:memory_high`, `:memory_max`, `:memory_swap_max` - bytes or `:max`
  * `:memory_oom_group` - boolean
  * `:pids_max` - count or `:max`
  * `:io_weight` - integer 1..10000
  * `:cpuset_cpus`, `:cpuset_mems` - range strings (e.g. `"0-3,5"`)

  See `cgroup_path/1` to retrieve the cgroup path itself, and
  `statistics/1` for the read-only stat files.
  """
  @spec cgroup_config(GenServer.server()) :: %{optional(atom()) => term()}
  def cgroup_config(server) do
    GenServer.call(server, :cgroup_config)
  end

  @doc """
  Return the daemon's cgroup path, or `nil` if the daemon isn't
  running under a cgroup.

  Paths are relative to `/sys/fs/cgroup`. For example, a daemon
  started with `cgroup_base: "muontrap"` might return
  `"muontrap/a1b2c3"`.
  """
  @spec cgroup_path(GenServer.server()) :: String.t() | nil
  def cgroup_path(server) do
    GenServer.call(server, :cgroup_path)
  end

  @doc """
  Return the OS pid to the muontrap executable.
  """
  @spec os_pid(GenServer.server()) :: non_neg_integer() | :error
  def os_pid(server) do
    GenServer.call(server, :os_pid)
  end

  @doc """
  Return statistics about the daemon.

  The following key is always present:

  * `:output_byte_count` - bytes output by the process being run

  When the daemon is running under a cgroup, the corresponding v2 interface
  files are read on each call and merged in. Files that don't exist (e.g.,
  the controller isn't enabled, or PSI isn't compiled into the kernel) are
  omitted rather than reported as errors.

  Possible cgroup keys:

  * `:memory_current`, `:memory_peak`, `:memory_swap_current` - bytes
  * `:memory_events` - flat-keyed map (`:low`, `:high`, `:max`, `:oom`,
    `:oom_kill`, ...)
  * `:memory_pressure`, `:cpu_pressure`, `:io_pressure` - PSI maps shaped
    like `%{some: %{avg10: 0.0, avg60: 0.0, avg300: 0.0, total: 0}, full: %{...}}`
  * `:cpu_stat` - flat-keyed map (`:usage_usec`, `:user_usec`, `:system_usec`,
    plus `:nr_periods`, `:nr_throttled`, `:throttled_usec` when `cpu.max` is set)
  * `:pids_current`, `:pids_peak` - counts
  * `:pids_events` - flat-keyed map (e.g. `:max`)
  * `:cgroup_stat` - flat-keyed map with `:nr_descendants`,
    `:nr_dying_descendants`

  See the kernel's `Documentation/admin-guide/cgroup-v2.rst` for the full
  semantics of each file.
  """
  @spec statistics(GenServer.server()) :: %{
          :output_byte_count => non_neg_integer(),
          optional(atom()) => term()
        }
  def statistics(server) do
    GenServer.call(server, :statistics)
  end

  @impl GenServer
  def init([command, args, opts]) do
    options = MuonTrap.Options.validate(:daemon, command, args, opts)
    port_options = MuonTrap.Port.port_options(options) ++ [:stream]

    # Logger.metadata/0 has a side effect to set the metadata for the current process
    options
    |> Map.get(:logger_metadata, [])
    |> Keyword.merge(muontrap_cmd: command, muontrap_args: Enum.join(args, " "))
    |> Logger.metadata()

    state = %__MODULE__{
      buffer: "",
      command: command,
      port: nil,
      port_options: port_options,
      cgroup_path: Map.get(options, :cgroup_path),
      logger_fun: logger_fun(options, command),
      exit_status_to_reason:
        Map.get(options, :exit_status_to_reason, fn _ -> :error_exit_status end),
      output_byte_count: 0,
      wait_task: nil
    }

    case Map.get(options, :wait_for) do
      nil -> {:ok, start_port(state)}
      fun -> {:ok, %{state | wait_task: Task.async(fun)}}
    end
  end

  defp start_port(state) do
    port =
      Port.open({:spawn_executable, to_charlist(MuonTrap.muontrap_path())}, state.port_options)

    %{state | port: port}
  end

  defp logger_fun(%{logger_fun: fun}, _command) when is_function(fun, 1), do: fun
  defp logger_fun(%{logger_fun: {m, f, a}}, _command), do: &apply(m, f, [&1 | a])

  defp logger_fun(options, command) do
    log_output = Map.get(options, :log_output)

    if log_output == nil do
      fn _line -> :ok end
    else
      log_prefix = Map.get(options, :log_prefix, command <> ": ")
      log_transform = Map.get(options, :log_transform, &default_transform/1)

      fn line ->
        Logger.log(log_output, [log_prefix, log_transform.(line)])
      end
    end
  end

  if Version.match?(System.version(), ">= 1.16.0") do
    defp default_transform(line) do
      String.replace_invalid(line)
    end
  else
    defp default_transform(line) do
      if String.valid?(line) do
        line
      else
        "** MuonTrap filtered #{byte_size(line)} non-UTF8 bytes **"
      end
    end
  end

  @impl GenServer
  def handle_call({:cgget, _variable_name}, _from, %{cgroup_path: nil} = state) do
    {:reply, {:error, :no_cgroup}, state}
  end

  def handle_call({:cgget, variable_name}, _from, %{cgroup_path: cgroup_path} = state) do
    result = Cgroups.cgget(cgroup_path, variable_name)

    {:reply, result, state}
  end

  def handle_call({:cgset, _variable_name, _value}, _from, %{cgroup_path: nil} = state) do
    {:reply, {:error, :no_cgroup}, state}
  end

  def handle_call(
        {:cgset, variable_name, value},
        _from,
        %{cgroup_path: cgroup_path} = state
      ) do
    result = Cgroups.cgset(cgroup_path, variable_name, value)

    {:reply, result, state}
  end

  def handle_call(:cgroup_config, _from, %{cgroup_path: cgroup_path} = state) do
    {:reply, Cgroups.config(cgroup_path), state}
  end

  def handle_call(:cgroup_path, _from, %{cgroup_path: cgroup_path} = state) do
    {:reply, cgroup_path, state}
  end

  def handle_call(:os_pid, _from, %__MODULE__{port: nil} = state) do
    {:reply, :error, state}
  end

  def handle_call(:os_pid, _from, state) do
    os_pid =
      case Port.info(state.port, :os_pid) do
        {:os_pid, p} -> p
        nil -> :error
      end

    {:reply, os_pid, state}
  end

  def handle_call(:statistics, _from, state) do
    statistics =
      state.cgroup_path
      |> Cgroups.statistics()
      |> Map.put(:output_byte_count, state.output_byte_count)

    {:reply, statistics, state}
  end

  @impl GenServer
  def handle_info({ref, _result}, %__MODULE__{wait_task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, start_port(%{state | wait_task: nil})}
  end

  def handle_info({port, {:data, message}}, %__MODULE__{port: port} = state) do
    bytes_received = byte_size(message)
    state = split_and_log(message, state)

    MuonTrap.Port.report_bytes_handled(state.port, bytes_received)

    {:noreply, %{state | output_byte_count: state.output_byte_count + bytes_received}}
  end

  def handle_info({port, {:exit_status, status}}, %__MODULE__{port: port} = state) do
    reason =
      case status do
        0 ->
          Logger.info("#{state.command}: Process exited successfully")
          :normal

        _failure ->
          Logger.error("#{state.command}: Process exited with status #{status}")
          state.exit_status_to_reason.(status)
      end

    {:stop, reason, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp split_and_log(data, state) do
    {lines, remainder} = process_data(state.buffer <> data)

    Enum.each(lines, &state.logger_fun.(&1))

    %{state | buffer: remainder}
  end

  @doc false
  @spec process_data(binary()) :: {[String.t()], binary()}
  def process_data(data) do
    data |> String.split("\n") |> process_lines([])
  end

  defp process_lines([leftovers], acc) do
    {Enum.reverse(acc), trim_buffer(leftovers)}
  end

  defp process_lines([line | rest], acc) do
    process_lines(rest, [line | acc])
  end

  defp trim_buffer(data) when byte_size(data) > @max_data_to_buffer,
    do: :binary.part(data, 0, @max_data_to_buffer)

  defp trim_buffer(data), do: data
end
