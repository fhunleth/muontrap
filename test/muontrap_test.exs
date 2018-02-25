defmodule MuonTrapTest do
  use ExUnit.Case
  import MuonTrapTestHelpers

  doctest MuonTrap

  test "closing the port kills the process" do
    port =
      Port.open({:spawn_executable, MuonTrap.muontrap_path()}, args: ["./test/do_nothing.test"])

    os_pid = os_pid(port)
    assert is_os_pid_around?(os_pid)

    Port.close(port)

    wait_for_close_check()
    assert !is_os_pid_around?(os_pid)
  end

  test "closing the port kills a process that ignores sigterm" do
    port =
      Port.open({:spawn_executable, MuonTrap.muontrap_path()}, args: ["test/ignore_sigterm.test"])

    os_pid = os_pid(port)
    assert is_os_pid_around?(os_pid)
    Port.close(port)

    wait_for_close_check()
    assert !is_os_pid_around?(os_pid)
  end

  test "delaying the SIGKILL" do
    port =
      Port.open(
        {:spawn_executable, MuonTrap.muontrap_path()},
        args: ["--delay-to-sigkill", "250000", "test/ignore_sigterm.test"]
      )

    os_pid = os_pid(port)
    assert is_os_pid_around?(os_pid)
    Port.close(port)

    Process.sleep(100)
    # process should be around for 250ms, so it should be around here.
    assert is_os_pid_around?(os_pid)

    Process.sleep(200)

    # Now it should be gone
    assert !is_os_pid_around?(os_pid)
  end
end
