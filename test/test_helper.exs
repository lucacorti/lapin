ExUnit.start()

defmodule LapinTest.HelloWorld do
  use Lapin.Connection
  require Logger

  def handle_deliver(channel, message) do
    Logger.debug(fn ->
      "Consuming message #{inspect(message, pretty: true)} received on #{
        inspect(channel, pretty: true)
      }"
    end)
  end
end
