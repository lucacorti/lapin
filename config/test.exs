use Mix.Config

alias Lapin.{Exchange, Queue}

config :lapin, :connections, [
  [
    module: LapinTest.Worker,
    consumers: [
      [
        pattern: Lapin.Consumer.WorkQueue,
        exchange: "test_exchange",
        queue: "test_queue",
        routing_key: "test_routing_key"
      ]
    ]
  ],
  [
    module: LapinTest.BadHostHelloWorld,
    uri: "amqp://thisisnotthedefault:nopass@nohosthere:9999",
  ]
]
