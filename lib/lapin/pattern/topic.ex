defmodule Lapin.Pattern.Topic do
  @moduledoc """
  Lapin.Pattern implementation for the
  [Topics](http://www.rabbitmq.com/tutorials/tutorial-five-elixir.html)
  RabbitMQ pattern.
  """

  use Lapin.Pattern

  def exchange_type(channel_config), do: Keyword.get(channel_config, :exchange_type, :topic)
  def routing_key(channel_config), do: Keyword.get(channel_config, :routing_key, "")
end
