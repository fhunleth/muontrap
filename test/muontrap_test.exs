defmodule MuonTrapTest do
  use ExUnit.Case
  import MuonTrapTestHelpers

  doctest MuonTrap

  test "closing the port kills the process" do
    port =
      Port.open({:spawn_executable, MuonTrap.muontrap_path()}, args: ["./test/do_nothing.test"])

    os_pid = os_pid(port)
    assert is_os_pid_around?(os_pid)

    Port.close(port)

    wait_for_close_check()
    assert !is_os_pid_around?(os_pid)
  end

  test "closing the port kills a process that ignores sigterm" do
    port =
      Port.open({:spawn_executable, MuonTrap.muontrap_path()}, args: ["test/ignore_sigterm.test"])

    os_pid = os_pid(port)
    assert is_os_pid_around?(os_pid)
    Port.close(port)

    wait_for_close_check()
    assert !is_os_pid_around?(os_pid)
  end

  test "delaying the SIGKILL" do
    port =
      Port.open(
        {:spawn_executable, MuonTrap.muontrap_path()},
        args: ["--delay-to-sigkill", "250000", "test/ignore_sigterm.test"]
      )

    os_pid = os_pid(port)
    assert is_os_pid_around?(os_pid)
    Port.close(port)

    Process.sleep(100)
    # process should be around for 250ms, so it should be around here.
    assert is_os_pid_around?(os_pid)

    Process.sleep(200)

    # Now it should be gone
    assert !is_os_pid_around?(os_pid)
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
      MuonTrap.cmd("ls", ['/usr'])
    end
  end

  test "cmd/2" do
    assert {"hello\n", 0} = MuonTrap.cmd("echo", ["hello"])
  end

  test "cmd/3 (with options)" do
    opts = [
      into: [],
      cd: System.cwd!(),
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
               MuonTrap.cmd(Path.join(System.cwd!(), @echo), ["hello"], [{:arg0, "echo"}])
    end)
  after
    File.rm_rf!(@tmp_path)
  end
end
