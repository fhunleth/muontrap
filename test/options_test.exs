defmodule OptionsTest do
  use ExUnit.Case
  alias MuonTrap.Options

  test "parses cgroup controllers" do
    {args, leftover_opts} = Options.to_args(cgroup_controllers: ["cpu", "memory"])
    assert args == ["--controller", "memory", "--controller", "cpu"]
    assert leftover_opts == []
  end

  test "parses cgroup path" do
    {args, leftover_opts} = Options.to_args(cgroup_path: "test/path")
    assert args == ["--group", "test/path"]
    assert leftover_opts == []
  end

  test "parses cgroup sets" do
    {args, leftover_opts} = Options.to_args(cgroup_sets: [{"cpu", "cpu.cfs_period_us", "100000"}])
    assert args == ["--controller", "cpu", "--set", "cpu.cfs_period_us=100000"]
    assert leftover_opts == []
  end

  test "parses cgroup sets 2" do
    {args, leftover_opts} =
      Options.to_args(
        cgroup_sets: [
          {"cpu", "cpu.cfs_period_us", "100000"},
          {"cpu", "cpu.cfs_quota_us", "50000"}
        ]
      )

    assert args == [
             "--controller",
             "cpu",
             "--set",
             "cpu.cfs_quota_us=50000",
             "--controller",
             "cpu",
             "--set",
             "cpu.cfs_period_us=100000"
           ]

    assert leftover_opts == []
  end

  test "parses uid" do
    {args, leftover_opts} = Options.to_args(uid: 1234)
    assert args == ["--uid", "1234"]
    assert leftover_opts == []

    {args, leftover_opts} = Options.to_args(uid: "bob")
    assert args == ["--uid", "bob"]
    assert leftover_opts == []
  end

  test "parses gid" do
    {args, leftover_opts} = Options.to_args(gid: 14)
    assert args == ["--gid", "14"]
    assert leftover_opts == []

    {args, leftover_opts} = Options.to_args(gid: "bob")
    assert args == ["--gid", "bob"]
    assert leftover_opts == []
  end

  test "parses delay-to-sigkill" do
    {args, leftover_opts} = Options.to_args(delay_to_sigkill: 123)
    assert args == ["--delay-to-sigkill", "123"]
    assert leftover_opts == []
  end

  test "ignores unknown options" do
    {args, leftover_opts} = Options.to_args(foo: :bar)
    assert args == []
    assert leftover_opts == [foo: :bar]
  end
end
