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

  test "daemon logs unhandled messages" do
    fun = fn ->
      {:ok, _pid} = start_supervised(daemon_spec("echo", ["hello"], name: UnhandledMsg))

      send(UnhandledMsg, "this is an unhandled msg")

      wait_for_close_check()
      Logger.flush()
    end

    assert capture_log(fun) =~ "Unhandled message: \"this is an unhandled msg\""
  end

  test "daemon dispatch the message to msg_callback" do
    fun = fn ->
      {:ok, _pid} =
        start_supervised(daemon_spec("echo", ["hello"], msg_callback: &msg_test_callback/1))

      wait_for_close_check()
      Logger.flush()
    end

    assert capture_log(fun) =~ "msg_callback echo says: hello"
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

  def msg_test_callback(msg) do
    require Logger
    Logger.log(:info, ["msg_callback echo says: ", msg])
  end
end
