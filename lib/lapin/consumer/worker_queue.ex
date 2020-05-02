defmodule Lapin.Consumer.WorkQueue do
  @moduledoc """
  `Lapin.Consumer` implementation for the
  [Work Queues](http://www.rabbitmq.com/tutorials/tutorial-two-elixir.html)
  RabbitMQ pattern.
  """
  use Lapin.Consumer

  def ack(%Consumer{config: config}), do: Keyword.get(config, :ack, true)

  def prefetch_count(%Consumer{config: config}), do: Keyword.get(config, :prefetch_count, 1)
end
