# Lapin, a RabbitMQ client for Elixir

## Description ###

**Lapin** is a *RabbitMQ* client for *Elixir* which abstracts away a lot of the
complexities of interacting with an *AMQP* broker.

While some advanced features, like [publisher confirms](http://www.rabbitmq.com/confirms.html),
are tied to *RabbitMQ* implementation specific extensions, **Lapin** should play
well with other broker implementations conforming to the AMQP 0.9.1 specification.

## Installation ##

Just add **Lapin** as a dependency to your `mix.exs`:

```
defp deps() do
  [{:lapin, ">= 0.0.0"}]
end
```

## Quick Start ##

If you are impatient to try **Lapin** out, just tweak this basic configuration
example:

```
config :lapin, :connections, [
  [
    virtual_host: "some_vhost",
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

```
defmodule MyApp.SomeWorker do
  use Lapin.Worker, patter: Lapin.Pattern.WorkQueue
end
```

To test your setup make sure *RabbitMQ* is running and configured correctly, then
run your application with `iex -S mix` and publish a message:

```
...
iex(1)> Lapin.Connection.publish("some_exchange", "some_queue", %Lapin.Message{payload: "test"})
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

You need to specify a worker module for all channels. To specify a custom module,
implement a custom `Lapin.Worker` module and adding it under the `worker` key in
your channel configuration. For details on implementing a custom worker module
check out the `Lapin.Worker` behaviour documentation.

At a minimum, you need to configure *virtual_host* for each connection and
*role*, *worker*, *exchange* and *queue* for each channel.
You can find a a complete list of connection configuration settings in the in
`Lapin.Connection` *config* type specification.

Advanced channel behaviour can be configured in two ways.

### One-shot, static configuration ###

If you are fine with a one shot configuration of your channels, you can specify
any settings from the `Lapin.Connection` *channel_config* type specification
directly in your channel configurations with the default `Lapin.Worker` module.

This is quick and easy way to start.

`lib/myapp/some_worker.ex`:

```
defmodule MyApp.SomeWorker do
  use Lapin.Worker
end
```

`config/config.exs`:

```
config :lapin, :connections, [
  [
    virtual_host: "some_vhost",
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

### Reusable, static or dynamic configuration ###

If you need to configure a lot of channels in the same way, you can *use* the
`Lapin.Pattern` to define channel settings. A pattern is simply a collection of
behaviour callbacks bundled in a module, which you can then reuse in any worker
module when you need the same behaviour in any channel.

To do this, you need to define your pattern module by *use* ing `Lapin.Pattern`
and specify it in your worker module by passing the *pattern* key when *use* ing
`Lapin.Worker`.

In fact `Lapin` bundles a few `Lapin.Pattern` modules implementing the
*RabbitMQ* [tutorials patterns](https://www.rabbitmq.org/getstarted.html).

`lib/myapp/some_pattern.ex`:

```
defmodule MyApp.SomePattern do
  use Lapin.Pattern

  def exchange_type(_channel_config): :fanout,
  def queue_durable(_channel_config): false  
  def publisher_persistent(_channel_config), do: true
end
```

`lib/myapp/some_worker.ex`:

```
defmodule MyApp.SomeWorker do
  use Lapin.Worker, pattern: MyApp.SomePattern
end
```

`config/config.exs`:

```
config :lapin, :connections, [
  [
    virtual_host: "some_vhost",
    channels: [
      [
        worker: MyApp.SomeWorker,
        role: :consumer,
        exchange: "some_exchange",
        queue: "some_queue",
      ],
      [
        worker: MyApp.SomeWorker,
        role: :producer,
        exchange: "some_exchange",
        queue: "some_queue",
      ]
    ]
  ]
]
```

Since a `Lapin.Pattern` is just a collection of overridable callback functions,
patterns also allow you to implement any kind of dynamic runtime configuration.

Actually, the one-shot static configuration explained earlier is implemented by
the default `Lapin.Pattern` module implementation which reads the configuration
file and tries to provide sensible defaults for unspecified settings.

## Usage ##

```
EXAMPLE NEEDED
```
