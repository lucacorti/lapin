defmodule LapinTest do
  use ExUnit.Case
  doctest Lapin

  alias Lapin.Connection

  setup_all do
    exchange = "test_exchange"
    queue = "test_queue"

    %{
      exchange: exchange,
      queue: queue,
      message: "",
      producer: [
        module: LapinTest.HelloWorld,
        virtual_host: "local",
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
        virtual_host: "local",
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
        virtual_host: "local",
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
      ]
    }
  end

  test "hello_world_producer_can_publish", ctx do
    {:ok, producer} = Connection.start_link(ctx.producer)
    :ok = Lapin.Connection.publish(producer, ctx.exchange, "", ctx.message)
    :ok = Lapin.Connection.close(producer)
  end

  test "hello_world_consumer_cant_publish", ctx do
    {:ok, consumer} = Connection.start_link(ctx.consumer)
    {:error, _} = Lapin.Connection.publish(consumer, ctx.exchange, "", ctx.message)
    :ok = Lapin.Connection.close(consumer)
  end

  test "hello_world_passive_cant_publish", ctx do
    {:ok, passive} = Connection.start_link(ctx.passive)
    {:error, _} = Lapin.Connection.publish(passive, ctx.exchange, "", ctx.message)
    :ok = Lapin.Connection.close(passive)
  end
end
