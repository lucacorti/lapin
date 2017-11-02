defmodule Lapin.Pattern.Routing do
  @moduledoc """
  Lapin.Pattern implementation for the
  [Routing](http://www.rabbitmq.com/tutorials/tutorial-four-elixir.html)
  RabbitMQ pattern.
  """
  use Lapin.Pattern

  def exchange_type(%Channel{config: config}), do: Keyword.get(config, :exchange_type, :direct)
  def routing_key(%Channel{config: config, routing_key: routing_key}), do: Keyword.get(config, :routing_key, routing_key)
end
