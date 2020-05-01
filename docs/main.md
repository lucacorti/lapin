# Lapin, a RabbitMQ client for Elixir

## Description

**Lapin** is a *RabbitMQ* client for *Elixir* which abstracts away a lot of the
complexities of interacting with an *AMQP* broker.

While some advanced features, like [publisher confirms](http://www.rabbitmq.com/confirms.html),
are tied to *RabbitMQ* implementation specific extensions, **Lapin** should play
well with other broker implementations conforming to the AMQP 0.9.1 specification.

## Installation

Just add **Lapin** as a dependency to your `mix.exs`:

```elixir
defp deps() do
  [{:lapin, ">= 0.0.0"}]
end
```

And add the `Lapin.Supervisor` under your application supervision tree:

```elixir
children = [
  supervisor(Lapin.Supervisor, [[], [name: Lapin.Supervisor]])
  ...
]
```

## Quick Start

If you are impatient to try **Lapin** out, just tweak this basic configuration
example:

```elixir
config :lapin, :connections, [
  [
    module: ExampleApp.Worker,
    consumers: [
      [queue: "some_queue"]
    ],
    producers: [
      [exchange: "some_exchange"]
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
iex(1)> ExampleApp.Worker.publish("some_exchange", "routing_key", "payload")
Published %Lapin.Message{meta: %{content_type: nil, mandatory: true, persistent: true}, payload: "msg"} on %Lapin.Producer{channel: %AMQP.Channel{conn: %AMQP.Connection{pid: #PID<0.305.0>}, pid: #PID<0.320.0>}, config: [pattern: Lapin.Producer.WorkQueue, exchange: "some_exchange"], exchange: "some_exchange", pattern: Lapin.Producer.WorkQueue}
:ok
[debug] Consuming message 1
[debug] Consumed message 1 successfully, ACK sent
...
```

Read on to learn how easy it is to tweak this basic configuration.

## Configuration

You can configure multiple connections. Each connection is backed by a worker
which can implement a few callbacks to publish/consume messages and handle other
type of events from the broker. Each connection can have one or more producers/consumers.

The default implementation of all callbacks simply returns `:ok`.

You need to configure a worker module for all connections. To implement a worker
module, define a module and use the `Lapin.Connection` behaviour, then add it
under the `module` key in your configuration.

For details on implementing *Lapin* worker modules check out the `Lapin.Connection`
behaviour documentation.

At a minimum, you need to configure a *module* for each connection, an *exchange*
for each producers and a *queue* for each consumer. You can find the complete list
of connection configuration settings in the in `Lapin.Connection` *config* type specification.

Advanced consumer/producer behaviour can be configured in two ways.

### One-shot, static consumer/producer configuration

If you are fine with one shot configuration of your comsumers/producers, you can specify
any settings from the `Lapin.Consumer`/`Lapin.Producer` `config` type specification
directly in your channel configurations.

This is quick and easy way to start.

`lib/example_app/some_worker.ex`:

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
    consumers: [
      [queue: "some_queue", ack: true]
    ],
    producers: [
      [exchange: "some_exchange", mandatory: true]
    ]
  ]
]
```

### Reusable, static or dynamic consumer/producer configuration

If you need to configure a lot of consumers/producers in the same way, you can use a
`Lapin.Consumer`/`Lapin.Producer` to define channel settings. A pattern is simply a collection of
behaviour callbacks bundled in a module, which you can then reuse in any channel
configuration when you need the same kind of interaction pattern.

To do this, you need to define your pattern module by `use Lapin.Pattern`
and specifying it in your in your channel configuration under the *pattern* key.

In fact `Lapin` bundles a few `Lapin.Pattern` implementations for the
*RabbitMQ* [tutorials patterns](https://www.rabbitmq.org/getstarted.html).

`lib/example_app/some_pattern.ex`:

```elixir
defmodule ExampleApp.Consumer do
  def ack(_channel), do: true
  def consumer_prefetch(_channel), do: 1
end

defmodule ExampleApp.Producer do
  use Lapin.Pattern

  def confirm(_channel), do: false  
  def mandatory(_channel), do: true
  def persistent(_channel), do: true
end
```

`config/config.exs`:

```elixir
config :lapin, :connections, [
  [
    module: ExampleApp.Worker
    consumers: [
      [queue: "some_queue", pattern: ExampleApp.Consumer]
    ],
    producers: [
      [exchange: "some_exchange", pattern: ExampleApp.Producer]
    ]
  ]
]
```

Since `Lapin.Consumer`/`Lapin.Producer` are just behaviours of overridable callback
functions, they also allow you to implement any kind of dynamic runtime configuration.

Actually, the one-shot static configuration explained earlier is implemented by
the default `Lapin.Consumer`/`Lapin.Producer` implementations which read settings
from the configuration and try to provide sensible defaults if needed.

### Declaring broker configuration

If you want to declare exchanges and queues with the broker you can do so in the configuration.
*Lapin* will just create a channel and declare exchanges, queues and bindings, reporting any
discrepancies between the configuration and the broker state if there are any.

```elixir
config :lapin, :connections, [
  module: ExampleApp.Worker,
  exchanges: [
    some_exchange: [
      type: :direct,
      options: [durable: true],
      binds: [
        some_queue: [routing_key: "some_routing_key"]
      ]
    ]
  ],
  queues: [
    some_queue: [
      options: [durable: true],
      binds: [
        some_exchange: [routing_key: "some_routing_key"]
      ]
    ]
  ],
  ...
]
```

Exchange declarations support `type` (*default: :direct*), `options` (see `AMQP.Exchange.declare/4`
for allowed types/options) and binds, which is a `keyword()` of queue names and declare arguments
(see `AMQP.Queue.bind/4` for allowed arguments).

Queue declarations support `options` (see `AMQP.Queue.declare/3` for allowed options) and binds,
which is a `keyword()` of exchange names and declare arguments (see `AMQP.Exchange.bind/4` for
allowed arguments).

## Usage

### Consuming messages

Once you have completed your configuration, connections will be automatically
established and channels will start receiving messages published on the queues
they are consuming.

You can handle received messages by overriding the `Lapin.Connection` `handle_deliver/2`
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

Since messages for all producers on the same connection are received by the same
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

Messages are considered to be successfully consumed if the `Lapin.Connection`
`handle_deliver/2` callback returns `:ok`. See the callback documentation for
a complete list of possible values you can return to signal message acknowledgement
and rejection to the broker.

### Publishing messages

To publish messages on channels you can use the `publish` function injected
in your worker module by `use Lapin.Connection`, or directly call
`Lapin.Connection.publish/5` by passing your worker module as a connection.

`config/config.exs`:

```elixir
config :lapin, :connections, [
  [
    module: ExampleApp.Worker,
    producers: [
      [exchange: "some_exchange"]
    ]
  ]
]
```

Using the worker module implementation:

```elixir
:ok = ExampleApp.Worker.publish("some_exchange", "routing_key", "payload", [])  
```

Via `Lapin.Connection` by passing the worker module as the connection:

```elixir
:ok = Lapin.Connection.publish(ExampleApp.Worker, "some_exchange", "routing_key", "payload", [])
```

If you are starting a `Lapin.Connection` manually, you can also pass the connection pid:

```elixir
{:ok, pid} = Lapin.Connection.start_link([
  module: ExampleApp.Worker,
  channels: [
    [
      pattern: ExampleApp.Pattern,
      exchange: "some_exchange",
      queue: "some_queue"
    ]
  ]
])

:ok = Lapin.Connection.publish(pid, "some_exchange", "routing_key", %Lapin.Message{}, [])
```

### Message payload encoding

Message payload is assumed to be `binary` by default, and is sent and received
unaltered by your code. However, Lapin can handle message encoding and decoding
for you.

Automatic encoding of the message payload is done by passing a data type other
than binary as the `payload` argument to the publish methods. And by providing
an implementation of the `Lapin.Message.Payload` protocol for your data type.

When consuming, the `Lapin.Connection` `payload_for/2` callback of the worker module
allows you to return an instance of the data type you want to perform message
decoding into. Again, an implementation of the `Lapin.Message.Payload` protocol
is required for your custom `payload` data type (e.g. a struct).

The `Lapin.Message.Payload` protocol documentation explains how to implement
the required functions, and provides an example JSON to struct implementation.
