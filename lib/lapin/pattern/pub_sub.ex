defmodule Lapin.Pattern.PubSub do
  @moduledoc """
  Lapin.Pattern implementation for the
  [Publish/Subscribe](http://www.rabbitmq.com/tutorials/tutorial-three-elixir.html)
  RabbitMQ pattern.
  """

  use Lapin.Pattern

  def exchange_type(channel_config), do: Keyword.get(channel_config, :exchange_type, :fanout)
end
