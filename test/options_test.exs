defmodule OptionsTest do
  use ExUnit.Case
  alias Shimmy.Options

  test "parses cgroup controllers" do
    {args, leftover_opts} = Options.to_args(cgroup_controllers: ["cpu", "memory"])
    assert args == ["--controller", "memory", "--controller", "cpu"]
    assert leftover_opts == []
  end

  test "ignores unknown options" do
    {args, leftover_opts} = Options.to_args(foo: :bar)
    assert args == []
    assert leftover_opts == [foo: :bar]
  end
end
