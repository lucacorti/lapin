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

defmodule LapinTest.BadHostWorker do
  use Lapin.Connection
end

defmodule LapinTest do
  use ExUnit.Case
  doctest Lapin

  defmodule LapinTest.HelloWorld do
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
        @binary_msg
      )
  end

  test "Error on publishing unroutable message" do
    {:error, _} =
      Lapin.Connection.publish(
        LapinTest.Worker,
        "test_exchange",
        "bad_routing_key",
        @binary_msg
      )
  end

  test "Bad host gets error on publish" do
    {:error, :not_connected} =
      Lapin.Connection.publish(LapinTest.BadHostHelloWorld, "test_badhost", "", @binary_msg)
  end
end
