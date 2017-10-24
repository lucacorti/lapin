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
    handle: :myhandle
    channels: [
      [
        worker: MyApp.SomeWorker,
        role: :consumer,
        exchange: "some_exchange",
        queue: "some_queue"
      ],
      [
        worker: MyApp.SomeWorker,
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
defmodule MyApp.SomeWorker do
  use Lapin.Worker, pattern: Lapin.Pattern.WorkQueue
end
```

To test your setup make sure *RabbitMQ* is running and configured correctly, then
run your application with `iex -S mix` and publish a message:

```elixir
...
iex(1)> Lapin.publish(:myhandle, "some_exchange", "some_queue", %Lapin.Message{payload: "test"})
[debug] Published to 'test'->'test': %Lapin.Message{meta: nil, payload: "test"}
:ok
[debug] Consuming message 1
[debug] Message 1 consumed successfully, with ACK
...
```

Read on to learn how easy it is to tweak this basic configuration.


## Configuration ##

You can configure multiple connections. Each connection is backed by a worker
which can implement a few callbacks to publish/consume messages and handle other
type of events from the broker. Each connection can have one or more
channels, each one either consuming *OR* publishing messages.

The default worker implementation simply logs events at log level `:debug`.

You need to configure a worker module for all channels. To implement a worker
module, define a module and use the `Lapin.Worker` behaviour, then add it under
the `worker` key in your channel configuration.

For details on implementing *Lapin* worker modules check out the `Lapin.Worker`
behaviour documentation.

At a minimum, you need to configure a *handle* for each connection and
*role*, *worker*, *exchange* and *queue* for each channel.

You can find a a complete list of connection configuration settings in the in
`Lapin.Connection` *config* type specification.

Advanced channel behaviour can be configured in two ways.

### One-shot, static channel configuration ###

If you are fine with a one shot configuration of your channels, you can specify
any settings from the `Lapin.Connection` *channel_config* type specification
directly in your channel configurations with the default `Lapin.Worker` module.

This is quick and easy way to start.

`lib/myapp/some_worker.ex`:

```elixir
defmodule MyApp.SomeWorker do
  use Lapin.Worker
end
```

`config/config.exs`:

```elixir
config :lapin, :connections, [
  [
    handle: :myhandle,
    channels: [
      [
        worker: MyApp.SomeWorker,
        role: :consumer,
        exchange: "some_exchange",
        queue: "some_queue",
        exchange_type: :fanout,
        queue_durable: false
      ],
      [
        worker: MyApp.SomeWorker,
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
behaviour callbacks bundled in a module, which you can then reuse in any worker
module when you need the same kind of interaction pattern in a channel.

To do this, you need to define your pattern module by *use* ing `Lapin.Pattern`
and specify it in your worker module by passing the *pattern* key when *use* ing
`Lapin.Worker`.

In fact `Lapin` bundles a few `Lapin.Pattern` modules implementing the
*RabbitMQ* [tutorials patterns](https://www.rabbitmq.org/getstarted.html).

`lib/myapp/some_pattern.ex`:

```elixir
defmodule MyApp.SomePattern do
  use Lapin.Pattern

  def exchange_type(_channel_config), do: :fanout,
  def queue_durable(_channel_config), do: false  
  def publisher_persistent(_channel_config), do: true
end
```

`lib/myapp/some_worker.ex`:

```elixir
defmodule MyApp.SomeWorker do
  use Lapin.Worker, pattern: MyApp.SomePattern
end
```

`config/config.exs`:

```elixir
config :lapin, :connections, [
  [
    channels: [
      [
        worker: MyApp.SomeWorker,
        role: :consumer,
        exchange: "some_exchange",
        queue: "some_queue"
      ],
      [
        worker: MyApp.SomeWorker,
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
established and the worker modules with `:consumer` role will start receiving
messages published on the queues they are consuming.

You can handle received messages by overriding the `Lapin.Worker.handle_deliver/2`
callback. The default implementation simply returns `:ok`.

```elixir
defmodule MyApp.SomeWorker do
  use Lapin.Worker, pattern: MyApp.SomePattern

  def handle_deliver(channel_config, message) do
    Logger.debug fn -> "received #{inspect message} on channel #{inspect channel_config}" end
  end
end
```

Messages are considered to be successfully consumed if the
`Lapin.Worker.handle_deliver/2` callback returns `:ok`. See the callback
documentation for a complete list of possible values you can return to signal
message acknowledgement and rejection to the broker.

### Publishing messages ###

To publish messages using workers with `:producer` role, you can use the
`Lapin.publish/5` function passing the connection handle for your connection,
or directly call `Lapin.Connection.publish/5` if you manually started a connection
with `Lapin.Connection.start_link/1`.

`config/config.exs`:

```elixir
config :lapin, :connections, [
  [
    handle: :myhandle,
    channels: [
      [
        role: :producer,
        worker: MyApp.SomeWorker,
        exchange: "some_exchange",
        queue: "some_queue"
      ]
    ]
  ]
]
```

Via `Lapin`:

```elixir
:ok = Lapin.publish(:myhandle, "some_exchange", "routing_key", %Lapin.Message{}, [])  
```

Via `Lapin.Connection` if you are starting a `Lapin.Connection` directly:

```elixir
{:ok, connection} = Lapin.Connection.start_link([
  handle: :myhandle,
  channels: [
    [
      role: :producer,
      worker: MyApp.SomeWorker,
      exchange: "some_exchange",
      queue: "some_queue"
    ]
  ]
])

:ok = Lapin.Connection.publish(connection, "some_exchange", "routing_key", %Lapin.Message{}, [])
```

### Declaring broker configuration ###

If you want to declare exchanges and queues without producing nor consuming
messages, you can set channel role to `:passive` in your channels.

This particular role does not allow publishing via messages and does not register
with the broker to consume the configured queue. *Lapin* will just create the
channel and declare exchanges, queues and queue bindings, reporting any
discrepancies between the configuration and the broker state if there are any.

```elixir
{:ok, connection} = Lapin.Connection.start_link([
  handle: :myhandle,
  channels: [
    [
      role: :passive,
      worker: MyApp.SomeWorker,
      exchange: "some_exchange",
      queue: "some_queue"
    ]
  ]
])

{:error, message} = Lapin.Connection.publish(connection, "some_exchange", "routing_key", %Lapin.Message{}, [])
```
