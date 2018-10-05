defmodule LapinTest do
  use ExUnit.Case
  doctest Lapin

  setup_all do
    exchange = "test_exchange"
    queue = "test_queue"

    %{
      exchange: exchange,
      queue: queue,
      message: "",
      producer: [
        module: LapinTest.HelloWorld,
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
        uri: "amqp://thisisnotthedefault:nopass@nohosthere:9999",
        channels: [
          [
            role: :producer,
            exchange: exchange,
            queue: queue
          ]
        ]
      ],
      default_exchange: [
        module: LapinTest.HelloWorld,
        channels: [
          [
            role: :producer,
            exchange: "",
            queue: queue,
            routing_key: queue,
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

  test "hello_world_does_not_declare_default_exchange", ctx do
    {:ok, default_exchange} = Lapin.Connection.start_link(ctx.default_exchange)
    :ok = Lapin.Connection.close(default_exchange)
  end

  test "hello_world_can_publish_on_default_exchange", ctx do
    {:ok, default_exchange} = Lapin.Connection.start_link(ctx.default_exchange)
    :ok = Lapin.Connection.publish(default_exchange, "", ctx.queue, ctx.message)
    :ok = Lapin.Connection.close(default_exchange)
  end
end
