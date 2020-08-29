defmodule ForceClosePortAfterTest do
  use MuonTrapTest.Case

  @temp_output_file "test/force_close_port_after_test_output.txt"
  @temp_output_text "Hello"
  @force_close_port_after_seconds 3
  @expected_output_count @force_close_port_after_seconds

  test "Test force_close_port_after" do
    ## Test that command currently not running
    assert [] == :os.cmd('ps -e | grep force_close_port_after_test')
    assert File.exists?(@temp_output_file) == false

    ## run command
    cmd_output =
      MuonTrap.cmd(
        "bash",
        ["test/force_close_port_after_test.sh", @temp_output_file, @temp_output_text],
        force_close_port_after: :timer.seconds(@force_close_port_after_seconds)
      )

    ## Test that force_close_port_after actually kicked in
    assert {"", -11} == cmd_output

    ## Test that command actually did run by checking if output file is present and contains the correct information
    assert File.exists?(@temp_output_file) == true

    assert @expected_output_count ==
             File.read!(@temp_output_file)
             |> String.split()
             |> Enum.count(fn x -> x == @temp_output_text end)

    ## Test that command currently not running (and make sure 'grep' process doesn't get counted)
    assert [] == :os.cmd('ps -e | grep [f]orce_close_port_after_test')

    ## tidy up
    File.rm(@temp_output_file)
  end
end
