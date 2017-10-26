defmodule Lapin.Pattern.Routing do
  @moduledoc """
  Lapin.Pattern implementation for the
  [Routing](http://www.rabbitmq.com/tutorials/tutorial-four-elixir.html)
  RabbitMQ pattern.
  """

  use Lapin.Pattern

  def exchange_type(_channel_config), do: :direct
  def routing_key(channel_config), do: Keyword.get(channel_config, :routing_key, "")
end
