use Mix.Config

alias Lapin.{Exchange, Queue}

config :lapin, :connections, [
  [
    module: LapinTest.Worker,
    exchanges: [
      [
        name: "test_exchange",
        binds: %{
          "test_queue" => [routing_key: "test_routing_key"]
        }
      ]
    ],
    queues: [
      [
        name: "test_queue",
        binds: %{
          "test_exchange" => [routing_key: "test_routing_key"]
        }
      ]
    ],
    consumers: [
      [
        pattern: Lapin.Consumer.WorkQueue,
        queue: "test_queue"
      ]
    ],
    producers: [
      [
        pattern: Lapin.Producer.WorkQueue,
        exchange: "test_exchange"
      ]
    ],
  ],
  [
    module: LapinTest.BadHostHelloWorld,
    uri: "amqp://thisisnotthedefault:nopass@nohosthere:9999",
  ]
]
