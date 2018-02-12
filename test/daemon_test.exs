defmodule DaemonTest do
  use ExUnit.Case
  import ShimmyTestHelpers

  alias Shimmy.Daemon

  test "stopping the daemon kills the process" do
    {:ok, pid} = Daemon.start_link("test/do_nothing.test", [])
    os_pid = Daemon.os_pid(pid)
    assert is_os_pid_around?(os_pid)

    GenServer.stop(pid)

    assert !is_os_pid_around?(os_pid)
  end
end
