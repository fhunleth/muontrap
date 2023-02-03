# SPDX-FileCopyrightText: 2018 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0

defmodule MuonTrap.Daemon do
  @moduledoc """
  Wrap an OS process in a GenServer so that it can be supervised.

  For example, in your children list add MuonTrap.Daemon like this:

  ```elixir
  children = [
    {MuonTrap.Daemon, ["my_server", ["--options", "foo")], [cd: "/some_directory"]]}
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

  defmodule State do
    @moduledoc false

    defstruct [
      :command,
      :port,
      :cgroup_path,
      :log_output,
      :log_prefix,
      :log_transform,
      :exit_status_to_reason
    ]
  end

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
  @spec os_pid(GenServer.server()) :: non_neg_integer()
  def os_pid(server) do
    GenServer.call(server, :os_pid)
  end

  @impl true
  def init([command, args, opts]) do
    options = MuonTrap.Options.validate(:daemon, command, args, opts)
    port_options = MuonTrap.Port.port_options(options) ++ [{:line, 256}]

    port = Port.open({:spawn_executable, to_charlist(MuonTrap.muontrap_path())}, port_options)

    {:ok,
     %State{
       command: command,
       port: port,
       cgroup_path: Map.get(options, :cgroup_path),
       log_output: Map.get(options, :log_output),
       log_prefix: Map.get(options, :log_prefix, command <> ": "),
       log_transform: Map.get(options, :log_transform, &Function.identity/1),
       exit_status_to_reason:
         Map.get(options, :exit_status_to_reason, fn _ -> :error_exit_status end)
     }}
  end

  @impl true
  def handle_call({:cgget, controller, variable_name}, _from, %{cgroup_path: cgroup_path} = state) do
    result = Cgroups.cgget(controller, cgroup_path, variable_name)

    {:reply, result, state}
  end

  @impl true
  def handle_call(
        {:cgset, controller, variable_name, value},
        _from,
        %{cgroup_path: cgroup_path} = state
      ) do
    result = Cgroups.cgset(controller, cgroup_path, variable_name, value)

    {:reply, result, state}
  end

  @impl true
  def handle_call(:os_pid, _from, state) do
    {:os_pid, os_pid} = Port.info(state.port, :os_pid)
    {:reply, os_pid, state}
  end

  @impl true
  def handle_info({_port, {:data, _}}, %State{log_output: nil} = state) do
    # Ignore output
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {port, {:data, {_, message}}},
        %State{
          port: port,
          log_output: log_level,
          log_prefix: prefix,
          log_transform: log_transform
        } = state
      ) do
    Logger.log(log_level, [prefix, log_transform.(message)])
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {port, {:exit_status, status}},
        %State{port: port, exit_status_to_reason: exit_status_to_reason} = state
      ) do
    reason =
      case status do
        0 ->
          Logger.info("#{state.command}: Process exited successfully")
          :normal

        _failure ->
          Logger.error("#{state.command}: Process exited with status #{status}")
          exit_status_to_reason.(status)
      end

    {:stop, reason, state}
  end
end
