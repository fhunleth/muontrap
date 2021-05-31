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
        Options.validate(context, "echo", ['not_a_binary'], [])
      end

      assert_raise ArgumentError, fn ->
        Options.validate(context, "why\0would_someone_do_this", [], [])
      end
    end
  end

  test "cmd and daemon-specific options" do
    # :cmd-only
    assert Map.get(Options.validate(:cmd, "echo", [], into: ""), :into) == ""

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
      Options.validate(:daemon, "echo", [], msg_callback: false)
    end

    raise_msg = "Invalid :msg_callback, only functions with /1 arity are allowed"

    assert_raise ArgumentError, raise_msg, fn ->
      Options.validate(:daemon, "echo", [], msg_callback: &Kernel.+/2)
    end

    :daemon
    |> Options.validate("echo", [], msg_callback: &inspect/1)
    |> Map.get(:msg_callback)
    |> Kernel.==(&inspect/1)
    |> assert()

    assert Map.get(Options.validate(:daemon, "echo", [], msg_callback: nil), :msg_callback) == nil
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
      assert Map.get(options, :env) == [{'KEY', 'VALUE'}, {'KEY2', 'VALUE2'}]
      assert Map.get(options, :cgroup_controllers) == ["memory", "cpu"]
      assert Map.get(options, :cgroup_base) == "base"
      assert Map.get(options, :cgroup_sets) == [{"memory", "memory.limit_in_bytes", "268435456"}]
    end
  end
end
