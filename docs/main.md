# Lapin, a RabbitMQ client for Elixir

## Description ###

`Lapin` is a *RabbitMQ* client for *Elixir* which abstracts away a lot of the
complexity of interacting with an *AMQP* broker.

While some advanced features are tied to *RabbitMQ* implementation specific
extensions like [publisher confirms](http://www.rabbitmq.com/confirms.html), it
should play well with other implementations conforming to the AMQP 0.9.1
specification.

## Installation ##

Just add `Lapin` as a dependency to your `mix.exs`:

```
defp deps() do
  [{:lapin, ">= 0.0.0"}]
end
```

## Quick Start ##

If you are impatient to try `Lapin` out, just tweak this basic configuration
example:

```
config :lapin, :connections, [
  [
    host: "some_hostname",
    port: "some_port",
    virtual_host: "some_vhost",
    channels: [
      [
        role: :consumer,
        exchange: "some_exchange",
        queue: "some_queue"
      ],
      [
        role: :producer,
        exchange: "another_exchange",
        queue: "another_queue"
      ]
    ]
  ]
]
```

Read on to learn how easy it is to tweak this basic configuration.


## Configuration ##

You can configure multiple connections. Each connection is backed by a worker
which must implement a number of callbacks to publish/consume messages or handle
other type of events from the broker. Each connection can have one or more
channels, each one either consuming *OR* publishing messages.

The default worker implementation simply logs events in development
mode.

For details on implementing a custom worker check out the `Lapin.Worker`
behaviour. You can specify a custom worker for any connection by putting implements
module name under the `worker` key in the connection configuration.

At a minimum, you need to configure *host*, *port* and *virtual_host*
for each connection and *role*, *exchange* and *queue* for each channel.
You can find a a complete list of connection configuration settings in the in
`Lapin.Worker` *connection_config* type specification.

Advanced channel behaviour can be configured in two ways.

### One-shot, static configuration ###

If you are fine with a one shot configuration all of your channels, you can
specify any settings from the `Lapin.Worker` *channel_config* type specification
directly in your channel configurations. This is quick and easy way to get going.

```
EXAMPLE NEEDED
```

### Reusable, static or dynamic configuration ###

If you need to configure a lot of channels in the same way, you can *use* the
`Lapin.Pattern` behaviour to define a custom *pattern*. A pattern is simply a
collection of callbacks bundled in a module, which you can then reuse when you
need the same behaviour in any channel. To do this, you need to define your and
specify it in your channels configuration under the *pattern* key.

Since a `Lapin.Pattern` is just a collection of overridable callback functions,
patterns also allow you to implement any kind of dynamic runtime configuration.

In fact the default implementation of `Lapin.Pattern` implements these
callbacks to read the static configuration file and provide sensible defaults.

```
EXAMPLE NEEDED
```

## Usage ##

```
EXAMPLE NEEDED
```
