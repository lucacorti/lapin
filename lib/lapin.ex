defmodule Lapin do
  @moduledoc """
  Lapin, an Elixir RabbitMQ client

  Comprehensive documentation is available [here](main.html).
  """

  alias Lapin.Connection

  @typedoc """
  Lapin configuration
  """
  @type config :: [connections: [Connection.config]]

  @doc """
  Publish a message to the connection with the specified handle
  """
  @spec publish(handle :: Connection.Registry.handle, exchange :: Connection.exchange,
  routing_key :: Connection.routing_key, message :: Lapin.Message.t, options :: Keyword.t) :: Worker.on_callback
  def publish(handle, exchange, routing_key, message, options \\ []) do
    via = Connection.Registry.via(handle)
    Connection.publish(via, exchange, routing_key, message, options)
  end
end
