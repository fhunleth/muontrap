defmodule ShimmyTest do
  use ExUnit.Case
  import ShimmyTestHelpers

  doctest Shimmy

  test "closing the port kills the process" do
    port = Port.open({:spawn_executable, Shimmy.shimmy_path()}, args: ["./test/do_nothing.test"])
    os_pid = os_pid(port)
    assert is_os_pid_around?(os_pid)

    Port.close(port)

    assert !is_os_pid_around?(os_pid)
  end

  test "closing the port kills a process that ignores sigterm" do
    port =
      Port.open({:spawn_executable, Shimmy.shimmy_path()}, args: ["test/ignore_sigterm.test"])

    os_pid = os_pid(port)
    assert is_os_pid_around?(os_pid)
    Port.close(port)

    assert !is_os_pid_around?(os_pid)
  end

  test "delaying the SIGKILL" do
    port =
      Port.open(
        {:spawn_executable, Shimmy.shimmy_path()},
        args: ["--delay-to-sigkill", "250000", "test/ignore_sigterm.test"]
      )

    os_pid = os_pid(port)
    assert is_os_pid_around?(os_pid)
    Port.close(port)

    # process should be around for 250ms, so it should be around here.
    assert is_os_pid_around?(os_pid)

    Process.sleep(300)

    assert !is_os_pid_around?(os_pid)
  end
end
