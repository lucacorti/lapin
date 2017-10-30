defmodule Lapin.Pattern.Topic do
  @moduledoc """
  Lapin.Pattern implementation for the
  [Topics](http://www.rabbitmq.com/tutorials/tutorial-five-elixir.html)
  RabbitMQ pattern.
  """

  use Lapin.Pattern

  def exchange_type(_channel), do: :topic
  def routing_key(channel), do: channel.routing_key
end
