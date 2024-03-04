# SPDX-FileCopyrightText: 2018 Frank Hunleth
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
  end

  test "common commands basically work" do
    input = [
      cd: "path",
      arg0: "arg0",
      stderr_to_stdout: true,
      parallelism: true,
      uid: 5,
      gid: "bill",
      delay_to_sigkill: 1,
      stdio_window: 1024,
      env: [{"KEY", "VALUE"}, {"KEY2", "VALUE2"}],
      cgroup_controllers: ["memory", "cpu"],
      cgroup_base: "base",
      cgroup_sets: [{"memory", "memory.limit_in_bytes", "268435456"}]
    ]

    for context <- [:daemon, :cmd] do
      options = Options.validate(context, "echo", [], input)

      assert Map.get(options, :cd) == "path"
      assert Map.get(options, :arg0) == "arg0"
      assert Map.get(options, :stderr_to_stdout) == true
      assert Map.get(options, :parallelism) == true
      assert Map.get(options, :uid) == 5
      assert Map.get(options, :gid) == "bill"
      assert Map.get(options, :delay_to_sigkill) == 1
      assert Map.get(options, :stdio_window) == 1024
      assert Map.get(options, :env) == [{~c"KEY", ~c"VALUE"}, {~c"KEY2", ~c"VALUE2"}]
      assert Map.get(options, :cgroup_controllers) == ["memory", "cpu"]
      assert Map.get(options, :cgroup_base) == "base"
      assert Map.get(options, :cgroup_sets) == [{"memory", "memory.limit_in_bytes", "268435456"}]
    end
  end
end
