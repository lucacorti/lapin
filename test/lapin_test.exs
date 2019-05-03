defmodule LapinTest do
  use ExUnit.Case
  doctest Lapin

  defmodule LapinTest.Worker do
    use Lapin.Connection
    require Logger

    def handle_deliver(consumer, message) do
      Logger.debug(fn ->
        "Consuming message #{inspect(message, pretty: true)} received on #{
          inspect(consumer, pretty: true)
        }"
      end)
    end
  end

  defmodule LapinTest.BadHostWorker do
    use Lapin.Connection
  end

  setup_all do
    %{}
  end

  test "Supervisor starts correctly", %{supervisor: supervisor} do
    assert supervisor
           |> Process.alive?()
  end

  test "Publish message via connection" do
    :ok =
      Lapin.Connection.publish(
        LapinTest.Worker,
        "test_exchange",
        "test_routing_key",
        "msg"
      )
  end

  test "Publish message via worker" do
    :ok =
      LapinTest.Worker.publish(
        "test_exchange",
        "test_routing_key",
        "msg"
      )
  end

  test "Bad host gets error on publish" do
    {:error, :not_connected} =
      Lapin.Connection.publish(LapinTest.BadHostWorker, "test_badhost", "", "msg")
  end
end
