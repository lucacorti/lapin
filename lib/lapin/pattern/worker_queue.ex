defmodule Lapin.Pattern.WorkQueue do
  @moduledoc """
  Lapin.Pattern implementation for the
  [Work Queues](http://www.rabbitmq.com/tutorials/tutorial-two-elixir.html)
  RabbitMQ pattern.
  """

  use Lapin.Pattern

  def consumer_ack(channel_config), do: Keyword.get(channel_config, :consumer_ack, true)
  def consumer_prefetch(channel_config), do: Keyword.get(channel_config, :consumer_prefetch, 1)
  def publisher_confirm(channel_config), do: Keyword.get(channel_config, :publisher_confirm, true)
  def publisher_mandatory(channel_config), do: Keyword.get(channel_config, :publisher_mandatory, true)
  def publisher_persistent(channel_config), do: Keyword.get(channel_config, :publisher_persistent, true)
  def routing_key(channel_config), do: Keyword.get(channel_config, :queue)
end
