defmodule Lapin.Pattern.Topic do
  @moduledoc """
  Lapin.Pattern implementation for the
  [Topics](http://www.rabbitmq.com/tutorials/tutorial-five-elixir.html)
  RabbitMQ pattern.
  """
  use Lapin.Pattern

  def exchange_type(%Channel{config: config}), do: Keyword.get(config, :exchange_type, :topic)
  def routing_key(%Channel{config: config, routing_key: routing_key}), do: Keyword.get(config, :routing_key, routing_key)
end
