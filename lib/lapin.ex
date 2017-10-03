defmodule Lapin do
  @moduledoc """
  Documentation for Lapin, an Elixir RabbitMQ client
  """

  defdelegate publish(exchange, queue, message), to: Lapin.Worker, as: :publish
end
