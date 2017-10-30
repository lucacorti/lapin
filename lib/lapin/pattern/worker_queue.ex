defmodule Lapin.Pattern.WorkQueue do
  @moduledoc """
  Lapin.Pattern implementation for the
  [Work Queues](http://www.rabbitmq.com/tutorials/tutorial-two-elixir.html)
  RabbitMQ pattern.
  """

  use Lapin.Pattern

  def consumer_ack(channel), do: Keyword.get(channel.config, :consumer_ack, true)
  def consumer_prefetch(channel), do: Keyword.get(channel.config, :consumer_prefetch, 1)
  def publisher_confirm(channel), do: Keyword.get(channel.config, :publisher_confirm, true)
  def publisher_mandatory(channel), do: Keyword.get(channel.config, :publisher_mandatory, true)
  def publisher_persistent(channel), do: Keyword.get(channel.config, :publisher_persistent, true)
  def routing_key(channel), do: Keyword.get(channel.config, :routing_key, channel.queue)
end
