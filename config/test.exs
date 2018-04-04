use Mix.Config

alias Lapin.{Exchange, Queue}

config :lapin, :connections, [
  [
    module: LapinTest.Worker,
    consumers: [
      [
        pattern: Lapin.Consumer.WorkQueue,
        queue: [name: "test_queue"]
      ]
    ],
    producers: [
      [
        pattern: Lapin.Producer.WorkQueue,
        exchange: [name: "test_exchange"]
      ]
    ],
  ],
  [
    module: LapinTest.BadHostHelloWorld,
    uri: "amqp://thisisnotthedefault:nopass@nohosthere:9999",
  ]
]
