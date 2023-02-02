ExUnit.start()

defmodule MuonTrapTestHelpers do
  @spec check_cgroup_support() :: :ok | no_return()
  def check_cgroup_support() do
    unless System.find_executable("cgget") do
      IO.puts(:stderr, "\nPlease install cgroup-tools so that cgcreate and cgget are available.")
      System.halt(0)
    end

    unless MuonTrapTest.Case.cpu_cgroup_exists("muontrap_test") and
             MuonTrapTest.Case.memory_cgroup_exists("muontrap_test") do
      IO.puts(:stderr, "\nPlease create the muontrap_test cgroup")
      IO.puts(:stderr, "sudo cgcreate -a $(whoami) -g memory,cpu:muontrap_test")
      System.halt(0)
    end
  end
end

case :os.type() do
  {:unix, :linux} ->
    MuonTrapTestHelpers.check_cgroup_support()

  _ ->
    IO.puts(:stderr, "Not on Linux so skipping tests that use cgroups...")
    ExUnit.configure(exclude: :cgroup)
end
