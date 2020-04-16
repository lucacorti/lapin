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

  setup_all do
    exchange = "test_exchange"
    queue = "test_queue"

    %{
      exchange: exchange,
      queue: queue,
      message: "",
      producer: [
        module: LapinTest.HelloWorld,
        username: "test",
        password: "test",
        channels: [
          [
            role: :producer,
            exchange: exchange,
            queue: queue
          ]
        ]
      ],
      consumer: [
        module: LapinTest.HelloWorld,
        username: "test",
        password: "test",
        channels: [
          [
            role: :consumer,
            exchange: exchange,
            queue: queue
          ]
        ]
      ],
      passive: [
        module: LapinTest.HelloWorld,
        username: "test",
        password: "test",
        channels: [
          [
            role: :passive,
            exchange: exchange,
            queue: queue
          ],
          [
            role: :passive,
            exchange: exchange,
            queue: queue
          ]
        ]
      ],
      bad_host: [
        module: LapinTest.HelloWorld,
        host: "nohosthere",
        port: 9999,
        username: "thisisnotthedefault",
        password: "nopass",
        channels: [
          [
            role: :producer,
            exchange: exchange,
            queue: queue
          ]
        ]
      ]
    }
  end

  test "hello_world_producer_can_publish", ctx do
    {:ok, producer} = Lapin.Connection.start_link(ctx.producer)
    :ok = Lapin.Connection.publish(producer, ctx.exchange, "", ctx.message)
    :ok = Lapin.Connection.close(producer)
  end

  test "hello_world_consumer_cant_publish", ctx do
    {:ok, consumer} = Lapin.Connection.start_link(ctx.consumer)
    {:error, _} = Lapin.Connection.publish(consumer, ctx.exchange, "", ctx.message)
    :ok = Lapin.Connection.close(consumer)
  end

  test "hello_world_passive_cant_publish", ctx do
    {:ok, passive} = Lapin.Connection.start_link(ctx.passive)
    {:error, _} = Lapin.Connection.publish(passive, ctx.exchange, "", ctx.message)
    :ok = Lapin.Connection.close(passive)
  end

  test "hello_world_bad_host_not_connected_error_on_publish", ctx do
    {:ok, bad_host} = Lapin.Connection.start_link(ctx.bad_host)
    {:error, :not_connected} = Lapin.Connection.publish(bad_host, ctx.exchange, "", ctx.message)
    :ok = Lapin.Connection.close(bad_host)
  end
end
