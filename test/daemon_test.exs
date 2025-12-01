# SPDX-FileCopyrightText: 2018 Frank Hunleth
# SPDX-FileCopyrightText: 2018 Matt Ludwigs
# SPDX-FileCopyrightText: 2019 Timmo Verlaan
# SPDX-FileCopyrightText: 2022 Gustavo Brunoro
# SPDX-FileCopyrightText: 2023 Ben Youngblood
# SPDX-FileCopyrightText: 2023 Eric Rauer
# SPDX-FileCopyrightText: 2023 Jon Carstens
# SPDX-FileCopyrightText: 2025 Fernando Mumbach
#
# SPDX-License-Identifier: Apache-2.0

defmodule DaemonTest do
  use MuonTrapTest.Case
  import ExUnit.CaptureLog
  import ExUnit.CaptureIO

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

  test "stopping the daemon kill very chatty processes" do
    fun = fn ->
      # Try up to 5 times to avoid false negatives. If the error is present, the
      # test will nearly always fail on the first iteration.
      for _ <- 1..5 do
        {:ok, pid} =
          start_supervised(daemon_spec(test_path("chatty.test"), [], log_output: :debug))

        os_pid = Daemon.os_pid(pid)
        assert_os_pid_running(os_pid)

        child_pid = find_child_pid(os_pid)
        assert is_integer(child_pid)

        :ok = stop_supervised(:test_daemon)

        wait_for_close_check()
        assert_os_pid_exited(os_pid)

        if os_pid_around?(child_pid) do
          System.cmd("kill", ["-9", "#{child_pid}"])
          flunk("muontrap process exited but child process was still running")
        end
      end
    end

    # For this test, it's critical to capture the log output even though we don't
    # use it; not doing so significantly increases the likelihood of false
    # negatives.
    capture_log([level: :info], fun)
  end

  @spec find_child_pid(non_neg_integer()) :: non_neg_integer() | nil
  def find_child_pid(os_pid) do
    {output, _} = System.cmd("ps", ["-eo", "ppid,pid"])

    output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      parsed_line = line |> String.trim() |> String.split(~r/\s+/)

      with [ppid, pid] <- parsed_line,
           true <- ppid == to_string(os_pid),
           {pid, ""} <- Integer.parse(pid) do
        pid
      else
        _ -> nil
      end
    end)
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
      {:ok, _pid} =
        start_supervised(daemon_spec(test_path("echo_stdio.test"), [], stderr_to_stdout: true))

      wait_for_close_check()

      Logger.flush()
    end

    assert capture_log(fun) == ""
  end

  test "daemon logs output to stderr when told" do
    fun = fn ->
      {:ok, pid} =
        start_supervised(
          daemon_spec(test_path("echo_stderr.test"), [],
            log_output: :error,
            stderr_to_stdout: true
          )
        )

      wait_for_output(pid, 15, 500)
      Logger.flush()
    end

    assert capture_log(fun) =~ "stderr message"
  end

  test "daemon does not log output to stderr when not told" do
    # Need to disable ANSI since new line in log message is important
    Application.put_env(:elixir, :ansi_enabled, false)

    fun = fn ->
      {:ok, pid} =
        start_supervised(
          daemon_spec(test_path("echo_stdio.test"), [],
            log_output: :error,
            stderr_to_stdout: false
          )
        )

      wait_for_output(pid, 12, 500)

      Logger.flush()
    end

    result = capture_log(fun)
    assert result =~ "echo_stdio.test: stdout here\n"
    refute result =~ ".."

    Application.delete_env(:elixir, :ansi_enabled)
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

  test "daemon logs include metadata" do
    fun = fn ->
      {:ok, _pid} =
        start_supervised(
          daemon_spec(
            "echo",
            ["-n", "hello"],
            log_output: :error,
            logger_metadata: [foo: :bar]
          )
        )

      wait_for_close_check()
      Logger.flush()
    end

    logger_opts = [
      metadata: [:foo, :muontrap_cmd, :muontrap_args],
      format: "[$level] $message $metadata\n"
    ]

    log_output = capture_log(logger_opts, fun)
    assert log_output =~ "foo=bar"
    assert log_output =~ "muontrap_cmd=echo"
    assert log_output =~ "muontrap_args=-n hello"
  end

  test "daemon supports custom logger (captured function)" do
    test_process = self()

    logger = fn line ->
      send(test_process, line)
    end

    fun = fn ->
      {:ok, pid} =
        start_supervised(
          daemon_spec(test_path("echo_stdio.test"), [],
            log_output: :error,
            logger_fun: logger,
            stderr_to_stdout: false
          )
        )

      wait_for_output(pid, 12, 500)

      Logger.flush()
    end

    log_output = capture_log(fun)

    refute log_output =~ "stdout here"

    assert_receive "stdout here", 500
    refute_receive _
  end

  test "daemon supports custom logger (mfa)" do
    fun = fn ->
      {:ok, pid} =
        start_supervised(
          daemon_spec(test_path("echo_stdio.test"), [],
            log_output: :error,
            logger_fun: {__MODULE__, :logger_fun_fun},
            stderr_to_stdout: false
          )
        )

      wait_for_output(pid, 12, 500)

      Logger.flush()
    end

    log_output = capture_log(fun)

    assert log_output =~ "stdout here"
    refute log_output =~ "logger_fun"

    stop_supervised(:test_daemon)

    fun = fn ->
      {:ok, pid} =
        start_supervised(
          daemon_spec(test_path("echo_stdio.test"), [],
            log_output: :error,
            logger_fun: {__MODULE__, :logger_fun_fun, ["logger_fun: "]},
            stderr_to_stdout: false
          )
        )

      wait_for_output(pid, 12, 500)

      Logger.flush()
    end

    log_output = capture_log(fun)

    assert log_output =~ "logger_fun: stdout here"
  end

  @spec logger_fun_fun(binary(), binary()) :: :ok
  def logger_fun_fun(line, prefix \\ "") do
    require Logger
    Logger.info([prefix, line])
  end

  defp wait_for_output(_pid, count, time_left) when time_left <= 0 do
    flunk("Didn't get #{count} output bytes from daemon process in time")
  end

  defp wait_for_output(pid, count, time_left) do
    got = Daemon.statistics(pid).output_byte_count

    cond do
      got < count ->
        Process.sleep(100)
        wait_for_output(pid, count, time_left - 100)

      got > count ->
        flunk("Got too much output: #{got}, but expected #{count}")

      true ->
        :ok
    end
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
    # Some systems may have SIGUSR1 == 10 and others
    # SIGUSR1 == 30. Do a quick lookup for the expected
    # signal mapping to decide which one to expect
    sigusr1 = s2n("USR1", 10)

    {:ok, pid} =
      start_supervised(
        daemon_spec(test_path("kill_self_with_sigusr1.test"), [],
          exit_status_to_reason: fn s ->
            if s == 128 + sigusr1 do
              :error_exit_sigusr1
            else
              {:error_exit_status, s}
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

  defp s2n(name, default) do
    with :error <- s2n_kill_l_name(name),
         :error <- s2n_kill_l(name) do
      default
    end
  end

  defp s2n_kill_l_name(name) do
    with {results, 0} <- System.cmd("kill", ["-l", name], stderr_to_stdout: true),
         {number, _} <- Integer.parse(results),
         true <- is_integer(number) do
      number
    else
      _ -> :error
    end
  end

  defp s2n_kill_l(name) do
    # Parse the result from MacOS kill.
    #
    # There are many formats for `kill -l` and this only supports the one on
    # MacOS that we're getting.
    case System.cmd("kill", ["-l"], stderr_to_stdout: true) do
      {signals, 0} ->
        String.split(signals)
        |> Enum.with_index(1)
        |> List.keyfind(name, 0, {:hack, :error})
        |> elem(1)

      _ ->
        :error
    end
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
    {memory, _} = Integer.parse(memory_str)
    assert memory > 1000
  end

  test "flow control when logging" do
    fun = fn ->
      {:ok, _pid} =
        start_supervised(
          daemon_spec(test_path("print_a_lot.test"), [],
            log_output: :error,
            stdio_window: 101
          )
        )

      wait_for_close_check(200)
      Logger.flush()
    end

    results = capture_log(fun)

    split =
      String.split(results, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    # Check that we have a log message for all 1000 lines plus the leftovers at the end.
    assert length(split) == 1001
  end

  test "line splits on newlines" do
    # Daemon.process_data(data) :: {lines, leftovers}
    assert {[], "abcd"} == Daemon.process_data("abcd")
    assert {["abcd"], ""} == Daemon.process_data("abcd\n")
    assert {["abcd", ""], ""} == Daemon.process_data("abcd\n\n")
    assert {[""], "abcd"} == Daemon.process_data("\nabcd")
    assert {["abcd"], ""} == Daemon.process_data("abcd\n")
    assert {["a", "b", "c", "d"], ""} == Daemon.process_data("a\nb\nc\nd\n")
  end

  test "line splits trim max amount to buffer" do
    a255 = :binary.copy("a", 255)
    a256 = :binary.copy("a", 256)
    a265 = :binary.copy("a", 265)

    # Trims amount to buffer when no newlines
    assert {[], a256} == Daemon.process_data(a265)

    # Doesn't trim if not needed
    assert {[], a255} == Daemon.process_data(a255)

    # Doesn't trim full lines if complete
    assert {[a265, "abcd"], "ef"} == Daemon.process_data(a265 <> "\nabcd\nef")

    # Trims leftovers and returns lines
    assert {["abc"], a256} == Daemon.process_data("abc\n" <> a265)
  end

  test "daemon inspects non-utf8 strings" do
    output =
      capture_io(:user, fn ->
        {:ok, pid} =
          start_supervised(daemon_spec(test_path("echo_junk.test"), [], log_output: :error))

        wait_for_output(pid, 15, 500)
        Logger.flush()
      end)

    refute output =~ "FORMATTER ERROR: bad return value"
    refute output =~ "** (RuntimeError) bad return value from Logger formatter Logger.Formatter"

    if Version.match?(System.version(), ">= 1.16.0") do
      assert output =~ "��ti�g!c"
    else
      assert output =~ "** MuonTrap filtered 14 non-UTF8 bytes **"
    end
  end

  test "daemon captures only stderr when capture_stderr_only is set" do
    fun = fn ->
      {:ok, pid} =
        start_supervised(
          daemon_spec(test_path("echo_both.test"), [],
            log_output: :error,
            capture_stderr_only: true
          )
        )

      wait_for_output(pid, 15, 500)
      Logger.flush()
    end

    log = capture_log(fun)
    assert log =~ "stderr message"
    refute log =~ "stdout message"
  end

  test "daemon captures stderr only without log_output (no crash)" do
    {:ok, pid} =
      start_supervised(
        daemon_spec(test_path("echo_stderr.test"), [],
          # no log_output & no logger_fun, so no logging
          # even if capture_stderr_only is true
          capture_stderr_only: true
        )
      )

    os_pid = Daemon.os_pid(pid)
    assert_os_pid_running(os_pid)

    wait_for_output(pid, 15, 500)

    :ok = stop_supervised(:test_daemon)

    wait_for_close_check()
    assert_os_pid_exited(os_pid)
  end

  test "daemon captures both stdout and stderr when both options are used" do
    fun = fn ->
      {:ok, pid} =
        start_supervised(
          daemon_spec(test_path("echo_both.test"), [],
            log_output: :error,
            stderr_to_stdout: true
          )
        )

      wait_for_output(pid, 30, 500)
      Logger.flush()
    end

    log = capture_log(fun)
    assert log =~ "stderr message"
    assert log =~ "stdout message"
  end

  test "daemon captures only stdout when stderr_to_stdout is false" do
    fun = fn ->
      {:ok, pid} =
        start_supervised(
          daemon_spec(test_path("echo_both.test"), [],
            log_output: :error,
            stderr_to_stdout: false
          )
        )

      wait_for_output(pid, 15, 500)
      Logger.flush()
    end

    log = capture_log(fun)
    refute log =~ "stderr message"
    assert log =~ "stdout message"
  end
end
