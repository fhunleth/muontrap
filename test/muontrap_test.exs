# SPDX-FileCopyrightText: 2018 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0

defmodule MuonTrapTest do
  use MuonTrapTest.Case

  doctest MuonTrap

  defp run_muontrap(args) do
    # Directly invoke the muontrap port to reduce the amount of code
    # to debug if something breaks.
    port =
      Port.open(
        {:spawn_executable, MuonTrap.muontrap_path()},
        args: args
      )

    # The port starts asynchronously. If the test needs to register
    # a signal handler, this is problematic since we can beat it.
    # The right answer is to handshake with our test helper app.
    # Since that's work, sleep briefly.
    Process.sleep(10)
    port
  end

  test "closing the port kills the process" do
    port = run_muontrap(["./test/do_nothing.test"])

    os_pid = os_pid(port)
    assert_os_pid_running(os_pid)

    Port.close(port)

    wait_for_close_check()
    assert_os_pid_exited(os_pid)
  end

  test "closing the port kills a process that ignores sigterm" do
    port = run_muontrap(["--delay-to-sigkill", "1", "test/ignore_sigterm.test"])

    os_pid = os_pid(port)
    assert_os_pid_running(os_pid)
    Port.close(port)

    wait_for_close_check()
    assert_os_pid_exited(os_pid)
  end

  test "delaying the SIGKILL" do
    port = run_muontrap(["--delay-to-sigkill", "250", "test/ignore_sigterm.test"])

    Process.sleep(10)
    os_pid = os_pid(port)
    assert_os_pid_running(os_pid)
    Port.close(port)

    Process.sleep(100)
    # process should be around for 250ms, so it should be around here.
    assert_os_pid_running(os_pid)

    Process.sleep(200)

    # Now it should be gone
    assert_os_pid_exited(os_pid)
  end

  # The following tests are copied from System.cmd to help ensure that
  # MuonTrap.cmd/3 works similarly.
  test "cmd/2 raises for null bytes" do
    assert_raise ArgumentError,
                 ~r"cannot execute MuonTrap.cmd/3 for program with null byte",
                 fn ->
                   MuonTrap.cmd("null\0byte", [])
                 end
  end

  test "cmd/3 raises with non-binary arguments" do
    assert_raise ArgumentError, ~r"all arguments for MuonTrap.cmd/3 must be binaries", fn ->
      MuonTrap.cmd("ls", [~c"/usr"])
    end
  end

  test "cmd/2" do
    assert {"hello\n", 0} = MuonTrap.cmd("echo", ["hello"])
  end

  test "cmd/3 (with options)" do
    opts = [
      into: [],
      cd: File.cwd!(),
      env: %{"foo" => "bar", "baz" => nil},
      arg0: "echo",
      stderr_to_stdout: true,
      parallelism: true
    ]

    assert {["hello\n"], 0} = MuonTrap.cmd("echo", ["hello"], opts)
  end

  @echo "echo-elixir-test"
  @tmp_path Path.join(__DIR__, "tmp")

  test "cmd/2 with absolute and relative paths" do
    File.mkdir_p!(@tmp_path)
    File.cp!(System.find_executable("echo"), Path.join(@tmp_path, @echo))

    File.cd!(@tmp_path, fn ->
      # There is a bug in OTP where find_executable is finding
      # entries on the current directory. If this is the case,
      # we should avoid the assertion below.
      unless System.find_executable(@echo) do
        assert :enoent = catch_error(MuonTrap.cmd(@echo, ["hello"]))
      end

      assert {"hello\n", 0} =
               MuonTrap.cmd(Path.join(File.cwd!(), @echo), ["hello"], [{:arg0, "echo"}])
    end)
  after
    File.rm_rf!(@tmp_path)
  end

  test "signals return an exit code of 128 + signal" do
    # SIGTERM == 15
    assert {"", 128 + 15} == MuonTrap.cmd(test_path("kill_self_with_signal.test"), [])
  end

  test "README.md version is up to date" do
    app = :muontrap
    app_version = Application.spec(app, :vsn) |> to_string()
    readme = File.read!("README.md")
    [_, readme_version] = Regex.run(~r/{:#{app}, "(.+)"}/, readme)
    assert Version.match?(app_version, readme_version)
  end
end
