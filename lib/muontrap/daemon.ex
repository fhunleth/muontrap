# SPDX-FileCopyrightText: 2018 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0

defmodule MuonTrap.Daemon do
  @moduledoc """
  Wrap an OS process in a GenServer so that it can be supervised.

  For example, in your children list add MuonTrap.Daemon like this:

  ```elixir
  children = [
    {MuonTrap.Daemon, ["my_server", ["--options", "foo"]], [cd: "/some_directory"]]}
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
  * `:exit_status_to_reason` - Optional function to convert the exit status (a
    number) to stop reason for the Daemon GenServer. Use if error exit codes
    carry information or aren't errors.

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
    :cgroup_path,
    :log_output,
    :log_prefix,
    :log_transform,
    :exit_status_to_reason,
    :output_byte_count
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
  Get the value of the specified cgroup variable.
  """
  @spec cgget(GenServer.server(), binary(), binary()) ::
          {:ok, String.t()} | {:error, File.posix()}
  def cgget(server, controller, variable_name) do
    GenServer.call(server, {:cgget, controller, variable_name})
  end

  @doc """
  Modify a cgroup variable.
  """
  @spec cgset(GenServer.server(), binary(), binary(), binary()) :: :ok | {:error, File.posix()}
  def cgset(server, controller, variable_name, value) do
    GenServer.call(server, {:cgset, controller, variable_name, value})
  end

  @doc """
  Return the OS pid to the muontrap executable.
  """
  @spec os_pid(GenServer.server()) :: non_neg_integer() | :error
  def os_pid(server) do
    GenServer.call(server, :os_pid)
  end

  @doc """
  Return statistics about the daemon

  Statistics:

  * `:output_byte_count` - bytes output by the process being run
  """
  @spec statistics(GenServer.server()) :: %{output_byte_count: non_neg_integer()}
  def statistics(server) do
    GenServer.call(server, :statistics)
  end

  @impl GenServer
  def init([command, args, opts]) do
    options = MuonTrap.Options.validate(:daemon, command, args, opts)
    port_options = MuonTrap.Port.port_options(options) ++ [:stream]

    port = Port.open({:spawn_executable, to_charlist(MuonTrap.muontrap_path())}, port_options)

    options
    |> Map.get(:logger_metadata, [])
    |> Keyword.merge(muontrap_cmd: command, muontrap_args: Enum.join(args, " "))
    |> Logger.metadata()

    {:ok,
     %__MODULE__{
       buffer: "",
       command: command,
       port: port,
       cgroup_path: Map.get(options, :cgroup_path),
       log_output: Map.get(options, :log_output),
       log_prefix: Map.get(options, :log_prefix, command <> ": "),
       log_transform: Map.get(options, :log_transform, &default_transform/1),
       exit_status_to_reason:
         Map.get(options, :exit_status_to_reason, fn _ -> :error_exit_status end),
       output_byte_count: 0
     }}
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
  def handle_call({:cgget, controller, variable_name}, _from, %{cgroup_path: cgroup_path} = state) do
    result = Cgroups.cgget(controller, cgroup_path, variable_name)

    {:reply, result, state}
  end

  def handle_call(
        {:cgset, controller, variable_name, value},
        _from,
        %{cgroup_path: cgroup_path} = state
      ) do
    result = Cgroups.cgset(controller, cgroup_path, variable_name, value)

    {:reply, result, state}
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
    statistics = %{output_byte_count: state.output_byte_count}
    {:reply, statistics, state}
  end

  @impl GenServer
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

    Enum.each(lines, &log_line(&1, state))

    %{state | buffer: remainder}
  end

  defp log_line(line, state) do
    Logger.log(state.log_output, [state.log_prefix, state.log_transform.(line)])
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
