# SPDX-FileCopyrightText: 2018 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0

defmodule CgroupTest do
  use MuonTrapTest.Case

  alias MuonTrap.Cgroups

  @tag :cgroup
  test "test environment cgroup support enabled" do
    assert Cgroups.cgroups_enabled?()

    {:ok, controllers} = Cgroups.get_controllers()
    # cpu and memory controllers need to be enabled for the unit tests
    assert "cpu" in controllers
    assert "memory" in controllers
  end

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

  @tag :cgroup
  test "get and set cgroup variables" do
    cgroup_path = random_cgroup_path()

    port =
      Port.open(
        {:spawn_executable, MuonTrap.muontrap_path()},
        args: ["-g", cgroup_path, "-c", "memory", "./test/do_nothing.test"]
      )

    os_pid = os_pid(port)
    assert_os_pid_running(os_pid)
    assert memory_cgroup_exists(cgroup_path)

    {:ok, memory_str} = Cgroups.cgget("memory", cgroup_path, "memory.limit_in_bytes")
    memory = Integer.parse(memory_str)
    assert memory > 1000

    # :ok = Cgroups.cgset("memory", cgroup_path, "memory.limit_in_bytes", "900")

    Port.close(port)
  end
end
