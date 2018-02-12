defmodule Shimmy.Daemon do
  use GenServer

  require Logger
  alias Shimmy.Options

  defmodule State do
    @moduledoc nil

    defstruct [:command, :port, :group]
  end

  def start_link(command, args, opts \\ []) do
    GenServer.start_link(__MODULE__, [command, args, opts])
  end

  @doc """
  Get the value of the specified cgroup variable.
  """
  def cgget(pid, controller, variable_name) do
    GenServer.call(pid, {:cgget, controller, variable_name})
  end

  def cgset(pid, controller, variable_name, value) do
    GenServer.call(pid, {:cgset, controller, variable_name, value})
  end

  @doc """
  Return the OS pid to the shimmy executable.
  """
  def os_pid(pid) do
    GenServer.call(pid, :os_pid)
  end

  def init([command, args, opts]) do
    group = Keyword.get(opts, :group)

    {shimmy_args, _updated_opts} = Options.to_args(opts)
    updated_args = shimmy_args ++ ["--", command] ++ args

    port = Port.open({:spawn_executable, Shimmy.shimmy_path()}, args: updated_args)

    {:ok, %State{command: command, port: port, group: group}}
  end

  def handle_call({:cgget, controller, variable_name}, _from, state) do
    result = System.cmd("cat", ["/sys/fs/cgroups/#{controller}/#{state.group}/#{variable_name}"])
    {:reply, result, state}
  end

  def handle_call({:cgset, controller, variable_name, value}, _from, state) do
    result = File.write!("/sys/fs/cgroups/#{controller}/#{state.group}/#{variable_name}", value)
    {:reply, result, state}
  end

  def handle_call(:os_pid, _from, state) do
    {:os_pid, os_pid} = Port.info(state.port, :os_pid)
    {:reply, os_pid, state}
  end

  def handle_info({port, {:data, message}}, %State{port: port} = state) do
    Logger.debug("#{state.command} #{inspect(message)}")
    {:noreply, state}
  end
end
