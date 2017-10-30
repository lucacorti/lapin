# Lapin, a RabbitMQ client for Elixir

## Description ###

**Lapin** is a *RabbitMQ* client for *Elixir* which abstracts away a lot of the
complexities of interacting with an *AMQP* broker.

While some advanced features, like [publisher confirms](http://www.rabbitmq.com/confirms.html),
are tied to *RabbitMQ* implementation specific extensions, **Lapin** should play
well with other broker implementations conforming to the AMQP 0.9.1 specification.

## Installation ##

Just add **Lapin** as a dependency to your `mix.exs`:

```elixir
defp deps() do
  [{:lapin, ">= 0.0.0"}]
end
```

## Quick Start ##

If you are impatient to try **Lapin** out, just tweak this basic configuration
example:

```elixir
config :lapin, :connections, [
  [
    module: ExampleApp.Worker
    channels: [
      [
        role: :consumer,
        exchange: "some_exchange",
        queue: "some_queue"
      ],
      [
        role: :producer,
        exchange: "some_exchange",
        queue: "some_queue"
      ]
    ]
  ]
]
```

and define your worker module as follows:

```elixir
defmodule ExampleApp.Worker do
  use Lapin.Connection
end
```

To test your setup make sure *RabbitMQ* is running and configured correctly, then
run your application with `iex -S mix` and publish a message:

```elixir
...
iex(1)> ExampleApp.Worker.publish("exchange", "routing_key", %Lapin.Message{payload: "test"})
[debug] Published %Lapin.Message{meta: %{content_type: nil, mandatory: false, persistent: false}, payload: ""} on %Lap
in.Channel{amqp_channel: %AMQP.Channel{conn: %AMQP.Connection{pid: #PID<0.212.0>}, pid: #PID<0.221.0>}, config: [role: :producer, e
xchange: "test_exchange", queue: "test_queue"], consumer_tag: nil, exchange: "test_exchange", pattern: Lapin.Pattern.Config, queue:
 "test_queue", role: :producer, routing_key: ""}
:ok
[debug] Consuming message 1
[debug] Consumed message 1 successfully, ACK sent
...
```

Read on to learn how easy it is to tweak this basic configuration.


## Configuration ##

You can configure multiple connections. Each connection is backed by a worker
which can implement a few callbacks to publish/consume messages and handle other
type of events from the broker. Each connection can have one or more
channels, each one either consuming *OR* publishing messages.

The default implementation of all callbacks simply returns `:ok`.

You need to configure a worker module for all connections. To implement a worker
module, define a module and use the `Lapin.Connection` behaviour, then add it
under the `module` key in your channel configuration.

For details on implementing *Lapin* worker modules check out the `Lapin.Connection`
behaviour documentation.

At a minimum, you need to configure a *module* for each connection and
*role*, *exchange* and *queue* for each channel. You can find the complete list
of connection configuration settings in the in `Lapin.Connection` *config* type
specification.

Advanced channel behaviour can be configured in two ways.

### One-shot, static channel configuration ###

If you are fine with a one shot configuration of your channels, you can specify
any settings from the `Lapin.Channel` *config* type specification
directly in your channel configurations and use the default `Lapin.Pattern`
implementation.

This is quick and easy way to start.

`lib/myapp/some_worker.ex`:

```elixir
defmodule ExampleApp.Worker do
  use Lapin.Connection
end
```

`config/config.exs`:

```elixir
config :lapin, :connections, [
  [
    module: ExampleApp.Worker,
    channels: [
      [
        role: :consumer,
        exchange: "some_exchange",
        queue: "some_queue",
        exchange_type: :fanout,
        queue_durable: false
      ],
      [
        role: :producer,
        exchange: "some_exchange",
        queue: "some_queue",
        publisher_persistent: true
      ]
    ]
  ]
]
```

### Reusable, static or dynamic channel configuration ###

If you need to configure a lot of channels in the same way, you can use a
`Lapin.Pattern` to define channel settings. A pattern is simply a collection of
behaviour callbacks bundled in a module, which you can then reuse in any channel
configuration when you need the same kind of interaction pattern.

To do this, you need to define your pattern module by `use Lapin.Pattern`
and specifying it in your in your channel configuration under the *pattern* key.

In fact `Lapin` bundles a few `Lapin.Pattern` implementations for the
*RabbitMQ* [tutorials patterns](https://www.rabbitmq.org/getstarted.html).

`lib/myapp/some_pattern.ex`:

```elixir
defmodule ExampleApp.Pattern do
  use Lapin.Pattern

  def exchange_type(_channel), do: :fanout,
  def queue_durable(_channel), do: false  
  def publisher_persistent(_channel), do: true
end
```

`config/config.exs`:

```elixir
config :lapin, :connections, [
  [
    module: ExampleApp.Worker
    channels: [
      [
        pattern: ExampleApp.Pattern,
        role: :consumer,
        exchange: "some_exchange",
        queue: "some_queue"
      ],
      [
        pattern: ExampleApp.Pattern,
        role: :producer,
        exchange: "some_exchange",
        queue: "some_queue"
      ]
    ]
  ]
]
```

Since `Lapin.Pattern` is just a behaviour of overridable callback functions,
patterns also allow you to implement any kind of dynamic runtime configuration.

Actually, the one-shot static configuration explained earlier is implemented by
the default `Lapin.Pattern.Config` module implementation which tries to read
settings from the configuration file and provides sensible defaults if needed.

## Usage ##

### Consuming messages ###

Once you have completed your configuration, connections will be automatically
established and channels with a `:consumer` role will start receiving
messages published on the queues they are consuming.

You can handle received messages by overriding the `Lapin.Connection.handle_deliver/2`
callback. The default implementation simply logs messages and returns `:ok`.

```elixir
defmodule ExampleApp.Worker do
  use Lapin.Connection

  def handle_deliver(channel, message) do
    Logger.debug fn -> "received #{inspect message} on #{inspect channel}" end
    :ok
  end
end
```

Since messages for all channels on the same connection are received by the same
worker module, to dispatch messages to different handling logic you can pattern
match on the `Channel.config` map which contains message routing information.

```elixir
defmodule ExampleApp.Worker do
  use Lapin.Connection

  def handle_deliver(%Channel{exchange: "a", queue: "b"} = channel, message) do
    Logger.debug fn -> "received #{inspect message} on #{inspect channel}" end
    :ok
  end

  def handle_deliver(%Channel{exchange: "c", queue: "d"} = channel, message) do
    Logger.debug fn -> "received #{inspect message} on #{inspect channel}" end
    :ok
  end
end
```

The `Lapin.Connection.payload_type/2` callback allows you to perform message
payload decoding into custom data types. Read the `Lapin.Message.Payload`
protocol documentation to know how to implement your decoding for your data types.

Messages are considered to be successfully consumed if the
`Lapin.Connection.handle_deliver/2` callback returns `:ok`. See the callback
documentation for a complete list of possible values you can return to signal
message acknowledgement and rejection to the broker.

### Publishing messages ###

To publish messages on channels with a `:producer` role, you can use the
`publish` function injected in your worker module by `use Lapin.Connection`,
or directly call `Lapin.Connection.publish/5` by passing your worker module as
a connection.

`config/config.exs`:

```elixir
config :lapin, :connections, [
  [
    module: ExampleApp.Worker,
    channels: [
      [
        role: :producer,
        exchange: "some_exchange",
        queue: "some_queue"
      ]
    ]
  ]
]
```

Using the woker module implementation:

```elixir
:ok = ExampleApp.Worker.publish("some_exchange", "routing_key", %Lapin.Message{}, [])  
```

Via `Lapin.Connection` by passing the worker module as the connection:

```elixir
:ok = Lapin.Connection.publish(ExampleApp.Worker, "some_exchange", "routing_key", %Lapin.Message{}, [])
```

If you are starting a `Lapin.Connection` manually, you can also pass the connection pid:

```elixir
{:ok, pid} = Lapin.Connection.start_link([
  module: ExampleApp.Worker,
  channels: [
    [
      role: :producer,
      pattern: ExampleApp.Pattern,
      exchange: "some_exchange",
      queue: "some_queue"
    ]
  ]
])

:ok = Lapin.Connection.publish(pid, "some_exchange", "routing_key", %Lapin.Message{}, [])
```

Message payload is assumed to be binary by default, but Lapin can handle message
encoding and decoding. To implement automatic encoding of the message payload you
can pass a custom data type as `payload` and implement the `Lapin.Message.Payload`
protocol for your data type.

Read the `Lapin.Message.Payload` protocol documentation to learn how to do this.

### Declaring broker configuration ###

If you want to declare exchanges and queues without producing nor consuming
messages, you can set channel role to `:passive` in your channels.

This particular role does not allow publishing via messages and does not register
with the broker to consume the configured queue. *Lapin* will just create the
channel and declare exchanges, queues and queue bindings, reporting any
discrepancies between the configuration and the broker state if there are any.

```elixir
{:ok, pid} = Lapin.Connection.start_link([
  module: ExampleApp.Worker,
  channels: [
    [
      role: :passive,
      exchange: "some_exchange",
      queue: "some_queue"
    ]
  ]
])

{:error, message} = Lapin.Connection.publish(pid, "some_exchange", "routing_key", %Lapin.Message{}, [])
```
