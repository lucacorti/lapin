defmodule Lapin.Pattern.WorkQueue do
  @moduledoc """
  Lapin.Pattern implementation for the
  [Work Queues](http://www.rabbitmq.com/tutorials/tutorial-two-elixir.html)
  RabbitMQ pattern.
  """
  use Lapin.Pattern

  def consumer_ack(%Channel{config: config}), do: Keyword.get(config, :consumer_ack, true)
  def consumer_prefetch(%Channel{config: config}), do: Keyword.get(config, :consumer_prefetch, 1)
  def publisher_confirm(%Channel{config: config}), do: Keyword.get(config, :publisher_confirm, true)
  def publisher_mandatory(%Channel{config: config}), do: Keyword.get(config, :publisher_mandatory, true)
  def publisher_persistent(%Channel{config: config}), do: Keyword.get(config, :publisher_persistent, true)
  def routing_key(%Channel{config: config, routing_key: routing_key}), do: Keyword.get(config, :routing_key, routing_key)
end
