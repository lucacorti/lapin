defmodule Lapin.Pattern.Routing do
  @moduledoc """
  Lapin.Pattern implementation for the
  [Routing](http://www.rabbitmq.com/tutorials/tutorial-four-elixir.html)
  RabbitMQ pattern.
  """

  use Lapin.Pattern

  def exchange_type(_channel), do: :direct
  def routing_key(channel), do: channel.routing_key
end
