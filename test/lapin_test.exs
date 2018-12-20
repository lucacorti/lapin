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

defmodule LapinTest do
  use ExUnit.Case
  doctest Lapin

  setup_all do
    {:ok, pid} = Lapin.Supervisor.start_link()
    %{supervisor: pid}
  end

  test "Supervisor starts correctly", %{supervisor: supervisor} do
    assert supervisor
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
      Lapin.Connection.publish(LapinTest.BadHostHelloWorld, "test_badhost", "", "msg")
  end
end
