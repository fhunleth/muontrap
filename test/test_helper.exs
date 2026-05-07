# SPDX-FileCopyrightText: 2018 Frank Hunleth
# SPDX-FileCopyrightText: 2023 Jon Carstens
#
# SPDX-License-Identifier: Apache-2.0

ExUnit.start()

defmodule MuonTrapTestHelpers do
  @spec check_cgroup_support() :: :ok | no_return()
  def check_cgroup_support() do
    if !(MuonTrapTest.Case.cpu_cgroup_exists("muontrap_test") and
           MuonTrapTest.Case.memory_cgroup_exists("muontrap_test")) do
      IO.puts(:stderr, """

      Please create the muontrap_test cgroup with cpu and memory enabled. Roughly:

        sudo mkdir -p /sys/fs/cgroup/muontrap_test
        sudo chown -R $(whoami) /sys/fs/cgroup/muontrap_test
        # Ensure cpu and memory are enabled in the parent's subtree_control. Run as root:
        echo +cpu +memory | sudo tee /sys/fs/cgroup/cgroup.subtree_control

      To skip cgroup tests, run `mix test --exclude cgroup`
      """)

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
