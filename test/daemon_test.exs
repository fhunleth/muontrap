# SPDX-FileCopyrightText: 2018 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0

defmodule DaemonTest do
  use MuonTrapTest.Case
  import ExUnit.CaptureLog

  alias MuonTrap.Daemon

  defp daemon_spec(cmd, args) do
    Supervisor.child_spec({Daemon, [cmd, args]}, id: :test_daemon)
  end

  defp daemon_spec(cmd, args, opts) do
    Supervisor.child_spec({Daemon, [cmd, args, opts]}, id: :test_daemon)
  end

  test "stopping the daemon kills the process" do
    {:ok, pid} = start_supervised(daemon_spec(test_path("do_nothing.test"), []))

    os_pid = Daemon.os_pid(pid)
    assert_os_pid_running(os_pid)

    :ok = stop_supervised(:test_daemon)

    wait_for_close_check()
    assert_os_pid_exited(os_pid)
  end

  test "daemon logs output when told" do
    fun = fn ->
      {:ok, _pid} = start_supervised(daemon_spec("echo", ["hello"], log_output: :error))

      wait_for_close_check()
      Logger.flush()
    end

    assert capture_log(fun) =~ "hello"
  end

  test "daemon logs are passed through log_transform fn" do
    fun = fn ->
      {:ok, _pid} =
        start_supervised(
          daemon_spec(
            "echo",
            ["hello"],
            log_output: :error,
            log_transform: &String.replace(&1, "hello", "goodbye")
          )
        )

      wait_for_close_check()
      Logger.flush()
    end

    assert capture_log(fun) =~ "goodbye"
  end

  test "daemon doesn't log output by default" do
    fun = fn ->
      {:ok, _pid} = start_supervised(daemon_spec("echo", ["hello"], stderr_to_stdout: true))

      wait_for_close_check()
      Logger.flush()
    end

    refute capture_log(fun) =~ "hello"
  end

  test "daemon logs output to stderr when told" do
    fun = fn ->
      {:ok, _pid} =
        start_supervised(
          daemon_spec(test_path("echo_stderr.test"), [],
            log_output: :error,
            stderr_to_stdout: true
          )
        )

      wait_for_close_check()
      Logger.flush()
    end

    assert capture_log(fun) =~ "stderr message"
  end

  test "daemon logs to a custom prefix" do
    fun = fn ->
      {:ok, _pid} =
        start_supervised(
          daemon_spec("echo", ["hello"], log_output: :error, log_prefix: "echo says: ")
        )

      wait_for_close_check()
      Logger.flush()
    end

    assert capture_log(fun) =~ "echo says: hello"
  end

  test "can pass environment variables to the daemon" do
    fun = fn ->
      {:ok, _pid} =
        start_supervised(
          daemon_spec(
            "env",
            [],
            log_output: :error,
            stderr_to_stdout: true,
            env: [{"MUONTRAP_TEST_VAR", "HELLO_THERE"}]
          )
        )

      wait_for_close_check()

      Logger.flush()
    end

    assert capture_log(fun) =~ "MUONTRAP_TEST_VAR=HELLO_THERE"
  end

  test "transient daemon restarts on errored exits" do
    # :transient means that successful exits don't restart, but
    # failed exits do.

    tempfile = Path.join("test", "tmp-transient_daemon")
    _ = File.rm(tempfile)

    log =
      capture_log(fn ->
        {:ok, _pid} =
          start_supervised(
            {Daemon, [test_path("succeed_second_time.test"), [tempfile], [log_output: :error]]},
            restart: :transient
          )

        # Give it time to run twice if successful or more than twice if not.
        Process.sleep(500)

        Logger.flush()
      end)

    _ = File.rm(tempfile)

    assert log =~ "Called 0 times"
    assert log =~ "Called 1 times"
    refute log =~ "Called 2 times"
  end

  test "permanent daemon always restarts" do
    tempfile = Path.join("test", "tmp-permanent_deamon")
    _ = File.rm(tempfile)

    log =
      capture_log(fn ->
        {:ok, _pid} =
          start_supervised(
            Supervisor.child_spec(
              {Daemon, [test_path("succeed_second_time.test"), [tempfile], [log_output: :error]]},
              restart: :permanent,
              id: :test_daemon
            )
          )

        # Give it time to restart a few times.
        Process.sleep(500)

        stop_supervised(:test_daemon)

        Logger.flush()
      end)

    _ = File.rm(tempfile)

    assert log =~ "Called 0 times"
    assert log =~ "Called 1 times"
    assert log =~ "Called 2 times"
  end

  test "returns :error_exit_status for stop reason" do
    {:ok, pid} = start_supervised(daemon_spec(test_path("kill_self_with_sigusr1.test"), []))

    ref = Process.monitor(pid)

    os_pid = Daemon.os_pid(pid)

    assert_receive {:DOWN, ^ref, :process, _object, :error_exit_status}
    assert_os_pid_exited(os_pid)

    :ok = stop_supervised(:test_daemon)

    wait_for_close_check()
  end

  test "supports mapping exit status to stop reason" do
    {signals, 0} = System.cmd("kill", ["-l"])

    # Some systems may have SIGUSR1 == 10 and others
    # SIGUSR1 == 30. Do a quick lookup for the expected
    # signal mapping to decide which one to expect
    sigusr1 =
      String.split(signals)
      |> Enum.with_index(129)
      |> Enum.find_value(fn {k, s} -> if k == "USR1", do: s end)

    assert is_integer(sigusr1)

    {:ok, pid} =
      start_supervised(
        daemon_spec(test_path("kill_self_with_sigusr1.test"), [],
          exit_status_to_reason: fn s ->
            if s == sigusr1 do
              :error_exit_sigusr1
            else
              :error_exit_status
            end
          end
        )
      )

    ref = Process.monitor(pid)

    os_pid = Daemon.os_pid(pid)

    assert_receive {:DOWN, ^ref, :process, _object, :error_exit_sigusr1}
    assert_os_pid_exited(os_pid)

    :ok = stop_supervised(:test_daemon)

    wait_for_close_check()
  end

  @tag :cgroup
  test "can start daemon with cgroups" do
    {:ok, pid} =
      start_supervised(
        daemon_spec(
          test_path("do_nothing.test"),
          [],
          cgroup_base: "muontrap_test",
          cgroup_controllers: ["memory"]
        )
      )

    os_pid = Daemon.os_pid(pid)
    assert_os_pid_running(os_pid)

    {:ok, memory_str} = Daemon.cgget(pid, "memory", "memory.limit_in_bytes")
    memory = Integer.parse(memory_str)
    assert memory > 1000
  end
end
