defmodule LapinTest do
  use ExUnit.Case
  doctest Lapin

  defmodule LapinTest.BadHostWorker do
    use Lapin.Connection
  end

  defmodule LapinTest.Worker do
    use Lapin.Connection
    require Logger

    def handle_deliver(channel, message) do
      Logger.debug(fn ->
        "Consuming message #{inspect(message, pretty: true)} received on #{
          inspect(channel, pretty: true)
        }"
      end)
    end
  end

  @binary_msg "msg"

  setup_all do
    %{}
  end

  test "Supervisor starts correctly" do
    Lapin.Connection.Supervisor
    |> Process.whereis()
    |> Process.alive?()
  end

  test "Publish message" do
    :ok =
      Lapin.Connection.publish(
        LapinTest.Worker,
        "test_exchange",
        "test_routing_key",
        "msg"
      )
  end

  test "Error on publishing unroutable message" do
    {:error, _} =
      Lapin.Connection.publish(
        LapinTest.Worker,
        "test_exchange",
        "bad_routing_key",
        "msg"
      )
  end

  test "Bad host gets error on publish" do
    {:error, :not_connected} =
      Lapin.Connection.publish(LapinTest.BadHostWorker, "test_badhost", "", "msg")
  end
end
