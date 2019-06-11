defmodule MuonTrap.Daemon do
  use GenServer

  require Logger
  alias MuonTrap.Options

  @moduledoc """
  Wrap an OS process in a GenServer so that it can be supervised.

  For example, in your children list add MuonTrap.Daemon like this:

  ```elixir
  children = [
    {MuonTrap.Daemon, ["myserver", ["--options", "foo")], [cd: "/somedirectory"]]}
  ]

  opts = [strategy: :one_for_one, name: MyApplication.Supervisor]
  Supervisor.start_link(children, opts)
  ```

  The same options as `MuonTrap.cmd/3` are available with the following additions:

  * `:log_output` - When set, send output from the command to the Logger. Specify the log level (e.g., `:debug`)
  * `:stderr_to_stdout` - When set to `true`, redirect stderr to stdout. Defaults to `false`.
  """

  defmodule State do
    @moduledoc false

    defstruct [:command, :port, :group, :log_output]
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, opts},
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
    GenServer.start_link(__MODULE__, [command, args, opts])
  end

  @doc """
  Get the value of the specified cgroup variable.
  """
  @spec cgget(GenServer.server(), binary(), binary()) :: binary()
  def cgget(server, controller, variable_name) do
    GenServer.call(server, {:cgget, controller, variable_name})
  end

  @doc """
  Modify a cgroup variable.
  """
  @spec cgset(GenServer.server(), binary(), binary(), binary()) :: :ok | no_return()
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
    group = Keyword.get(opts, :group)
    logging = Keyword.get(opts, :log_output)
    stderr_to_stdout = Keyword.get(opts, :stderr_to_stdout, false)
    opts = Keyword.drop(opts, [:log_output, :stderr_to_stdout])

    opts = add_stderr_to_stdout(opts, stderr_to_stdout)

    {muontrap_args, leftover_opts} = Options.to_args(opts)
    updated_args = muontrap_args ++ ["--", command] ++ args

    port_options = [:exit_status, {:args, updated_args}, {:line, 256} | leftover_opts]
    port = Port.open({:spawn_executable, to_charlist(MuonTrap.muontrap_path())}, port_options)

    {:ok, %State{command: command, port: port, group: group, log_output: logging}}
  end

  @impl true
  def handle_call({:cgget, controller, variable_name}, _from, state) do
    result = System.cmd("cat", ["/sys/fs/cgroups/#{controller}/#{state.group}/#{variable_name}"])
    {:reply, result, state}
  end

  @impl true
  def handle_call({:cgset, controller, variable_name, value}, _from, state) do
    result = File.write!("/sys/fs/cgroups/#{controller}/#{state.group}/#{variable_name}", value)
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
        %State{port: port, log_output: log_level} = state
      ) do
    _ = Logger.log(log_level, "#{state.command}: #{message}")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %State{port: port} = state) do
    _ = Logger.error("#{state.command}: Process exited with status #{status}")
    {:stop, :normal, state}
  end

  defp add_stderr_to_stdout(opts, true), do: [:stderr_to_stdout | opts]
  defp add_stderr_to_stdout(opts, false), do: opts
end
