# SPDX-FileCopyrightText: 2018 Frank Hunleth
# SPDX-FileCopyrightText: 2023 Jon Carstens
#
# SPDX-License-Identifier: Apache-2.0

ExUnit.start()

defmodule MuonTrapTestHelpers do
  @spec check_cgroup_support() :: :ok | no_return()
  def check_cgroup_support() do
    if !System.find_executable("cgget") do
      IO.puts(:stderr, "\nPlease install cgroup-tools so that cgcreate and cgget are available.")
      IO.puts(:stderr, "\nTo skip cgroup tests, run `mix test --exclude cgroup`")
      System.halt(1)
    end

    if !(MuonTrapTest.Case.cpu_cgroup_exists("muontrap_test") and
           MuonTrapTest.Case.memory_cgroup_exists("muontrap_test")) do
      IO.puts(:stderr, "\nPlease create the muontrap_test cgroup")
      IO.puts(:stderr, "sudo cgcreate -a $(whoami) -g memory,cpu:muontrap_test")
      IO.puts(:stderr, "\nTo skip cgroup tests, run `mix test --exclude cgroup`")
      System.halt(1)
    end
  end

  @spec cgroup_excluded?() :: boolean
  def cgroup_excluded?() do
    excludes = ExUnit.configuration()[:exclude]

    :cgroup in excludes or truthy?(Keyword.get(excludes, :cgroup))
  end

  defp truthy?("false"), do: false
  defp truthy?(false), do: false
  defp truthy?(nil), do: false
  defp truthy?(_), do: true
end

if !MuonTrapTestHelpers.cgroup_excluded?() do
  case :os.type() do
    {:unix, :linux} ->
      MuonTrapTestHelpers.check_cgroup_support()

    _ ->
      IO.puts(:stderr, "Not on Linux so skipping tests that use cgroups...")
      ExUnit.configure(exclude: :cgroup)
  end
end
