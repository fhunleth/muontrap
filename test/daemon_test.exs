defmodule DaemonTest do
  use MuonTrapTest.Case
  import ExUnit.CaptureLog

  alias MuonTrap.Daemon

  test "stopping the daemon kills the process" do
    {:ok, pid} = Daemon.start_link("test/do_nothing.test", [])
    os_pid = Daemon.os_pid(pid)
    assert_os_pid_running(os_pid)

    GenServer.stop(pid)

    wait_for_close_check()
    assert_os_pid_exited(os_pid)
  end

  test "exiting the process ends the daemon" do
    assert capture_log(fn ->
             {:ok, pid} = GenServer.start(Daemon, ["echo", ["hello"], []])

             wait_for_close_check()
             refute Process.alive?(pid)
           end) =~ "[error] echo: Process exited with status 0"
  end

  test "daemon logs output when told" do
    fun = fn ->
      {:ok, _pid} = GenServer.start(Daemon, ["echo", ["hello"], [log_output: :error]])
      wait_for_close_check()
      Logger.flush()
    end

    assert capture_log(fun) =~ "hello"
  end

  test "daemon doesn't log output by default" do
    fun = fn ->
      {:ok, _pid} = GenServer.start(Daemon, ["echo", ["hello"], []])
      wait_for_close_check()
      Logger.flush()
    end

    refute capture_log(fun) =~ "hello"
  end

  test "daemon logs output to stderr when told" do
    opts = [log_output: :error, stderr_to_stdout: true]

    fun = fn ->
      {:ok, _pid} = GenServer.start(Daemon, ["test/echo_stderr.test", [], opts])
      wait_for_close_check()
      Logger.flush()
    end

    assert capture_log(fun) =~ "stderr message"
  end

  test "can pass environment variables to the daemon" do
    fun = fn ->
      {:ok, _pid} =
        GenServer.start(Daemon, [
          "env",
          [],
          [log_output: :error, env: [{"MUONTRAP_TEST_VAR", "HELLO_THERE"}]]
        ])

      wait_for_close_check()
      Logger.flush()
    end

    assert capture_log(fun) =~ "MUONTRAP_TEST_VAR=HELLO_THERE"
  end
end
