defmodule LapinTest do
  use ExUnit.Case
  doctest Lapin

  defmodule Worker do
    use Lapin.Connection
    require Logger

    @impl Lapin.Connection
    def handle_deliver(consumer, message) do
      Logger.debug(fn ->
        "Consuming message #{inspect(message, pretty: true)} received on #{inspect(consumer, pretty: true)}"
      end)
    end
  end

  defmodule BadHostWorker do
    use Lapin.Connection
  end

  setup_all do
    {:ok, pid} = Lapin.Supervisor.start_link()
    %{supervisor: pid}
  end

  test "Supervisor starts correctly", %{supervisor: supervisor} do
    assert Process.alive?(supervisor)
  end

  test "Publish message via connection" do
    :ok = LapinTest.Worker.publish("test_exchange", "test_routing_key", "msg")
  end

  test "Publish message via worker" do
    :ok = LapinTest.Worker.publish("test_exchange", "test_routing_key", "msg")
  end

  test "Bad host gets error on publish" do
    {:error, :not_connected} = LapinTest.BadHostWorker.publish("test_badhost", "", "msg")
  end
end
