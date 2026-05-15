# SPDX-FileCopyrightText: 2018 Frank Hunleth
# SPDX-FileCopyrightText: 2023 Ben Youngblood
# SPDX-FileCopyrightText: 2023 Jon Carstens
#
# SPDX-License-Identifier: Apache-2.0

defmodule MuonTrap.OptionsTest do
  use MuonTrapTest.Case

  alias MuonTrap.Options

  test "creates random cgroup path when asked" do
    options = Options.validate(:cmd, "echo", [], cgroup_base: "base")
    assert Map.has_key?(options, :cgroup_path)

    ["base", other] = String.split(options.cgroup_path, "/")
    assert byte_size(other) > 4
  end

  test "disallow both cgroup_path and cgroup_base" do
    assert_raise ArgumentError, fn ->
      Options.validate(:cmd, "echo", [], cgroup_base: "base", cgroup_path: "path")
    end
  end

  test "errors match System.cmd ones" do
    for context <- [:cmd, :daemon] do
      # :enoent on missing executable
      assert catch_error(Options.validate(context, "__this_should_not_exist", [], [])) == :enoent

      assert_raise ArgumentError, fn ->
        Options.validate(context, "echo", [~c"not_a_binary"], [])
      end

      assert_raise ArgumentError, fn ->
        Options.validate(context, "why\0would_someone_do_this", [], [])
      end
    end
  end

  test "cmd and daemon-specific options" do
    # :cmd-only
    assert Map.get(Options.validate(:cmd, "echo", [], into: ""), :into) == ""
    assert Map.get(Options.validate(:cmd, "echo", [], timeout: 1000), :timeout) == 1000

    assert_raise ArgumentError, fn ->
      Options.validate(:daemon, "echo", [], into: "")
    end

    # :daemon-only
    assert Map.get(Options.validate(:daemon, "echo", [], name: Something), :name) == Something

    assert_raise ArgumentError, fn ->
      Options.validate(:cmd, "echo", [], name: Something)
    end

    for level <- [:error, :warn, :info, :debug] do
      assert Map.get(Options.validate(:daemon, "echo", [], log_output: level), :log_output) ==
               level

      assert_raise ArgumentError, fn ->
        Options.validate(:cmd, "echo", [], log_output: level)
      end
    end

    assert_raise ArgumentError, fn ->
      Options.validate(:daemon, "echo", [], log_output: :bad_level)
    end

    assert_raise ArgumentError, fn ->
      Options.validate(:daemon, "echo", [], timeout: 1000)
    end

    assert Map.get(
             Options.validate(:daemon, "echo", [], logger_metadata: [foo: :bar]),
             :logger_metadata
           ) == [foo: :bar]

    assert_raise ArgumentError, fn ->
      Options.validate(:cmd, "echo", [], logger_metadata: [foo: :bar])
    end

    assert is_function(
             Map.get(
               Options.validate(:daemon, "echo", [], logger_fun: &Function.identity/1),
               :logger_fun
             )
           )

    assert {Function, :identity, []} =
             Map.get(
               Options.validate(:daemon, "echo", [], logger_fun: {Function, :identity, []}),
               :logger_fun
             )

    assert {Function, :identity, []} =
             Map.get(
               Options.validate(:daemon, "echo", [], logger_fun: {Function, :identity}),
               :logger_fun
             )

    assert_raise ArgumentError, fn ->
      Options.validate(:daemon, "echo", [], logger_fun: &DateTime.add/2)
    end

    assert_raise ArgumentError, fn ->
      Options.validate(:cmd, "echo", [], logger_fun: &Function.identity/1)
    end

    # :wait_for is :daemon-only and must be a 0-arity function
    wait_fun = fn -> :ok end

    assert is_function(
             Map.get(Options.validate(:daemon, "echo", [], wait_for: wait_fun), :wait_for),
             0
           )

    assert_raise ArgumentError, fn ->
      Options.validate(:cmd, "echo", [], wait_for: wait_fun)
    end

    assert_raise ArgumentError, fn ->
      Options.validate(:daemon, "echo", [], wait_for: :not_a_fun)
    end

    assert_raise ArgumentError, fn ->
      Options.validate(:daemon, "echo", [], wait_for: &Function.identity/1)
    end
  end

  test "common commands basically work" do
    input = [
      cd: "path",
      arg0: "arg0",
      stderr_to_stdout: true,
      capture_stderr_only: true,
      parallelism: true,
      uid: 5,
      gid: "bill",
      delay_to_sigkill: 1,
      stdio_window: 1024,
      env: [{"KEY", "VALUE"}, {"KEY2", "VALUE2"}],
      cgroup_base: "base",
      cgroup: %{memory_max: 268_435_456, cpu_weight: 50}
    ]

    for context <- [:daemon, :cmd] do
      options = Options.validate(context, "echo", [], input)

      assert Map.get(options, :cd) == "path"
      assert Map.get(options, :arg0) == "arg0"
      assert Map.get(options, :stderr_to_stdout) == true
      assert Map.get(options, :capture_stderr_only) == true
      assert Map.get(options, :parallelism) == true
      assert Map.get(options, :uid) == 5
      assert Map.get(options, :gid) == "bill"
      assert Map.get(options, :delay_to_sigkill) == 1
      assert Map.get(options, :stdio_window) == 1024
      assert Map.get(options, :env) == [{~c"KEY", ~c"VALUE"}, {~c"KEY2", ~c"VALUE2"}]
      assert Map.get(options, :cgroup_base) == "base"
      assert Enum.sort(Map.get(options, :cgroup_controllers)) == ["cpu", "memory"]

      assert Enum.sort(Map.get(options, :cgroup_sets)) ==
               Enum.sort([
                 {"memory", "memory.max", "268435456"},
                 {"cpu", "cpu.weight", "50"}
               ])
    end
  end

  test "translates a cgroup map with sentinel and tuple values" do
    options =
      Options.validate(:daemon, "echo", [],
        cgroup_path: "muontrap/abc",
        cgroup: %{
          memory_max: 500_000_000,
          memory_high: :max,
          cpu_max: {50_000, 100_000},
          memory_oom_group: true
        }
      )

    assert options.cgroup_path == "muontrap/abc"
    assert Enum.sort(options.cgroup_controllers) == ["cpu", "memory"]

    assert Enum.sort(options.cgroup_sets) ==
             Enum.sort([
               {"memory", "memory.max", "500000000"},
               {"memory", "memory.high", "max"},
               {"memory", "memory.oom.group", "1"},
               {"cpu", "cpu.max", "50000 100000"}
             ])
  end

  test "rejects unknown cgroup config keys (including a stale :cgroup_path)" do
    assert_raise ArgumentError, ~r/unknown cgroup config field/, fn ->
      Options.validate(:daemon, "echo", [], cgroup: %{bogus_key: 1})
    end

    assert_raise ArgumentError, ~r/unknown cgroup config field.*cgroup_path/, fn ->
      Options.validate(:daemon, "echo", [], cgroup: %{cgroup_path: "x"})
    end
  end

  test "rejects malformed cgroup values" do
    assert_raise ArgumentError, ~r/invalid value/, fn ->
      Options.validate(:daemon, "echo", [], cgroup: %{memory_max: -1})
    end

    assert_raise ArgumentError, ~r/invalid value/, fn ->
      Options.validate(:daemon, "echo", [], cgroup: %{cpu_max: {-1, 100}})
    end

    assert_raise ArgumentError, ~r/invalid value/, fn ->
      Options.validate(:daemon, "echo", [], cgroup: %{memory_max: "500M"})
    end
  end

  test "accepts :groups list of integers and binaries (including empty)" do
    options = Options.validate(:cmd, "echo", [], groups: [10, "audio", 100])
    assert options.groups == [10, "audio", 100]

    options = Options.validate(:cmd, "echo", [], groups: [])
    assert options.groups == []
  end

  test "rejects malformed :groups entries" do
    assert_raise ArgumentError, ~r/invalid :groups entry/, fn ->
      Options.validate(:cmd, "echo", [], groups: [10, -1])
    end

    assert_raise ArgumentError, ~r/invalid :groups entry/, fn ->
      Options.validate(:cmd, "echo", [], groups: [10, :atom])
    end

    assert_raise ArgumentError, ~r/invalid :groups entry/, fn ->
      Options.validate(:cmd, "echo", [], groups: [""])
    end

    assert_raise ArgumentError, ~r/invalid :groups entry/, fn ->
      Options.validate(:cmd, "echo", [], groups: ["audio,video"])
    end

    assert_raise ArgumentError, ~r/invalid option :groups/, fn ->
      Options.validate(:cmd, "echo", [], groups: "audio")
    end
  end
end
