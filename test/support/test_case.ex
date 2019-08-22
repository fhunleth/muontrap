defmodule MuonTrapTest.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__)
      alias MuonTrapTest.Case
    end
  end

  @timeout_before_close_check 20

  @spec test_path(Path.t()) :: Path.t()
  def test_path(cmd) do
    Path.join([File.cwd!(), "test", cmd])
  end

  @spec cpu_cgroup_exists(String.t()) :: boolean
  def cpu_cgroup_exists(path) do
    {rc, 0} = System.cmd("cgget", ["-g", "cpu", path], stderr_to_stdout: true)
    String.match?(rc, ~r/cpu.shares/)
  end

  @spec memory_cgroup_exists(String.t()) :: boolean
  def memory_cgroup_exists(path) do
    {rc, 0} = System.cmd("cgget", ["-g", "memory", path], stderr_to_stdout: true)
    String.match?(rc, ~r/memory.stat/)
  end

  @spec random_cgroup_path :: String.t()
  def random_cgroup_path() do
    "muontrap_test/test#{:rand.uniform(10000)}"
  end

  @spec is_os_pid_around?(non_neg_integer()) :: boolean
  def is_os_pid_around?(os_pid) do
    {_, rc} = System.cmd("ps", ["-p", "#{os_pid}"])
    rc == 0
  end

  @spec assert_os_pid_running(non_neg_integer()) :: :ok
  def assert_os_pid_running(os_pid) do
    is_os_pid_around?(os_pid) || flunk("Expected OS pid #{os_pid} to still be running")
    :ok
  end

  @spec assert_os_pid_exited(non_neg_integer()) :: :ok
  def assert_os_pid_exited(os_pid) do
    is_os_pid_around?(os_pid) && flunk("Expected OS pid #{os_pid} to be killed")
    :ok
  end

  @spec os_pid(port()) :: non_neg_integer()
  def os_pid(port) do
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    os_pid
  end

  @spec wait_for_close_check(non_neg_integer()) :: :ok
  def wait_for_close_check(timeout \\ @timeout_before_close_check) do
    Process.sleep(timeout)
  end
end
