# SPDX-FileCopyrightText: 2018 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0

defmodule MuonTrapPortTest do
  use ExUnit.Case

  test "handles basic port call" do
    options = %{cmd: "/bin/echo", args: ["1", "2", "3"]}
    port_options = MuonTrap.Port.port_options(options)

    assert port_options == [
             :use_stdio,
             :exit_status,
             :binary,
             :hide,
             {:args, ["--", "/bin/echo", "1", "2", "3"]}
           ]
  end

  test "handles cgroup controllers" do
    options = %{cmd: "/bin/echo", args: [], cgroup_controllers: ["cpu", "memory"]}
    port_options = MuonTrap.Port.port_options(options)

    assert Keyword.get(port_options, :args) == [
             "--controller",
             "cpu",
             "--controller",
             "memory",
             "--",
             "/bin/echo"
           ]
  end

  test "handles cgroup path" do
    options = %{cmd: "/bin/echo", args: [], cgroup_path: "test/path"}
    port_options = MuonTrap.Port.port_options(options)

    assert Keyword.get(port_options, :args) == [
             "--group",
             "test/path",
             "--",
             "/bin/echo"
           ]
  end

  test "handles cgroup sets" do
    options = %{cmd: "/bin/echo", args: [], cgroup_sets: [{"cpu", "cpu.cfs_period_us", "100000"}]}
    port_options = MuonTrap.Port.port_options(options)

    assert Keyword.get(port_options, :args) == [
             "--controller",
             "cpu",
             "--set",
             "cpu.cfs_period_us=100000",
             "--",
             "/bin/echo"
           ]
  end

  test "handles cgroup sets 2" do
    options = %{
      cmd: "/bin/echo",
      args: [],
      cgroup_sets: [{"cpu", "cpu.cfs_period_us", "100000"}, {"cpu", "cpu.cfs_quota_us", "50000"}]
    }

    port_options = MuonTrap.Port.port_options(options)

    assert Keyword.get(port_options, :args) == [
             "--controller",
             "cpu",
             "--set",
             "cpu.cfs_period_us=100000",
             "--controller",
             "cpu",
             "--set",
             "cpu.cfs_quota_us=50000",
             "--",
             "/bin/echo"
           ]
  end

  test "handles uid" do
    options = %{
      cmd: "/bin/echo",
      args: [],
      uid: 1234
    }

    port_options = MuonTrap.Port.port_options(options)

    assert Keyword.get(port_options, :args) == [
             "--uid",
             "1234",
             "--",
             "/bin/echo"
           ]

    options = %{
      cmd: "/bin/echo",
      args: [],
      uid: "bob"
    }

    port_options = MuonTrap.Port.port_options(options)

    assert Keyword.get(port_options, :args) == [
             "--uid",
             "bob",
             "--",
             "/bin/echo"
           ]
  end

  test "handles gid" do
    options = %{
      cmd: "/bin/echo",
      args: [],
      gid: 14
    }

    port_options = MuonTrap.Port.port_options(options)

    assert Keyword.get(port_options, :args) == [
             "--gid",
             "14",
             "--",
             "/bin/echo"
           ]

    options = %{
      cmd: "/bin/echo",
      args: [],
      gid: "bob"
    }

    port_options = MuonTrap.Port.port_options(options)

    assert Keyword.get(port_options, :args) == [
             "--gid",
             "bob",
             "--",
             "/bin/echo"
           ]
  end

  test "parses delay-to-sigkill" do
    options = %{
      cmd: "/bin/echo",
      args: [],
      delay_to_sigkill: 123
    }

    port_options = MuonTrap.Port.port_options(options)

    assert Keyword.get(port_options, :args) == [
             "--delay-to-sigkill",
             "123",
             "--",
             "/bin/echo"
           ]
  end

  test "parses stdio-window" do
    options = %{
      cmd: "/bin/echo",
      args: [],
      stdio_window: 32
    }

    port_options = MuonTrap.Port.port_options(options)

    assert Keyword.get(port_options, :args) == [
             "--stdio-window",
             "32",
             "--",
             "/bin/echo"
           ]
  end

  defp encode_acks(number) do
    number
    |> MuonTrap.Port.encode_acks()
    |> IO.iodata_to_binary()
  end

  test "ack calculation" do
    assert encode_acks(1) == <<0>>
    assert encode_acks(10) == <<9>>
    assert encode_acks(256) == <<255>>
    assert encode_acks(257) == <<255, 0>>
    assert encode_acks(512) == <<255, 255>>
    assert encode_acks(513) == <<255, 255, 0>>
  end
end
