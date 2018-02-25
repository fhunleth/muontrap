ExUnit.start()

defmodule MuonTrapTestHelpers do
  @timeout_before_close_check 10

  def cpu_cgroup_exists(path) do
    {rc, 0} = System.cmd("cgget", ["-g", "cpu", path], stderr_to_stdout: true)
    String.match?(rc, ~r/cpu.shares/)
  end

  def memory_cgroup_exists(path) do
    {rc, 0} = System.cmd("cgget", ["-g", "memory", path], stderr_to_stdout: true)
    String.match?(rc, ~r/memory.stat/)
  end

  def check_cgroup_support() do
    unless System.find_executable("cgget") do
      IO.puts(:stderr, "\nPlease install cgroup-tools so that cgcreate and cgget are available.")
      System.halt(0)
    end

    unless cpu_cgroup_exists("muontrap_test") and memory_cgroup_exists("muontrap_test") do
      IO.puts(:stderr, "\nPlease create the muontrap_test cgroup")
      IO.puts(:stderr, "sudo cgcreate -a $(whoami) -g memory,cpu:muontrap_test")
      System.halt(0)
    end
  end

  def random_cgroup_path() do
    "muontrap_test/test#{:rand.uniform(10000)}"
  end

  def is_os_pid_around?(os_pid) do
    {_, rc} = System.cmd("ps", ["-p", "#{os_pid}"])
    rc == 0
  end

  def os_pid(port) do
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    os_pid
  end

  def wait_for_close_check(timeout \\ @timeout_before_close_check) do
    Process.sleep(timeout)
  end
end

case :os.type() do
  {:unix, :linux} ->
    MuonTrapTestHelpers.check_cgroup_support()

  _ ->
    IO.puts(:stderr, "Not on Linux so skipping tests that use cgroups...")
    ExUnit.configure(exclude: :cgroup)
end
