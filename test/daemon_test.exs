defmodule DaemonTest do
  use ExUnit.Case
  import MuonTrapTestHelpers

  alias MuonTrap.Daemon

  test "stopping the daemon kills the process" do
    {:ok, pid} = Daemon.start_link("test/do_nothing.test", [])
    os_pid = Daemon.os_pid(pid)
    assert is_os_pid_around?(os_pid)

    GenServer.stop(pid)

    wait_for_close_check()
    assert !is_os_pid_around?(os_pid)
  end

  test "exiting the process ends the daemon" do
    {:ok, pid} = GenServer.start(Daemon, ["echo", ["hello"], []])

    wait_for_close_check()
    refute Process.alive?(pid)
  end
end
