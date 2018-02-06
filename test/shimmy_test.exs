defmodule ShimmyTest do
  use ExUnit.Case
  doctest Shimmy

  test "greets the world" do
    assert Shimmy.hello() == :world
  end
end
