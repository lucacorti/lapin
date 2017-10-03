defmodule LapinTest do
  use ExUnit.Case
  doctest Lapin

  test "greets the world" do
    assert Lapin.hello() == :world
  end
end
