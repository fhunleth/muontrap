defmodule CgroupTest do
  use MuonTrapTest.Case

  @tag :cgroup
  test "cgroup gets created and removed on exit" do
    cgroup_path = random_cgroup_path()

    port =
      Port.open(
        {:spawn_executable, MuonTrap.muontrap_path()},
        args: ["-g", cgroup_path, "-c", "cpu", "./test/do_nothing.test"]
      )

    os_pid = os_pid(port)
    assert_os_pid_running(os_pid)
    assert cpu_cgroup_exists(cgroup_path)

    Port.close(port)

    wait_for_close_check()
    assert_os_pid_exited(os_pid)
    assert !cpu_cgroup_exists(cgroup_path)
  end

  @tag :cgroup
  test "cleans up after a forking process" do
    cgroup_path = random_cgroup_path()

    port =
      Port.open(
        {:spawn_executable, MuonTrap.muontrap_path()},
        args: ["-g", cgroup_path, "-c", "cpu", "./test/fork_a_lot.test"]
      )

    os_pid = os_pid(port)
    assert_os_pid_running(os_pid)
    assert cpu_cgroup_exists(cgroup_path)

    Port.close(port)

    wait_for_close_check()
    assert_os_pid_exited(os_pid)
    assert !cpu_cgroup_exists(cgroup_path)
  end
end
