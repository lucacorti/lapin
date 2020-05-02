use Mix.Config

alias LapinTest.BadHostWorker
alias Lapin.{Consumer, Producer}

config :lapin, :connections, [
  [
    module: LapinTest.Worker,
    user: "test",
    password: "test",
    exchanges: [
      test_exchange: [
        binds: [
          test_queue: [routing_key: "test_routing_key"]
        ]
      ]
    ],
    queues: [
      test_queue: [
        binds: [
          test_exchange: [routing_key: "test_routing_key"]
        ]
      ]
    ],
    consumers: [
      [
        pattern: Consumer.WorkQueue,
        queue: "test_queue"
      ]
    ],
    producers: [
      [
        pattern: Producer.WorkQueue,
        exchange: "test_exchange"
      ]
    ]
  ],
  [
    module: BadHostWorker,
    uri: "amqp://thisisnotthedefault:nopass@nohosthere:9999"
  ]
]
