defmodule Lapin.Producer.WorkQueue do
  @moduledoc """
  `Lapin.Producer` implementation for the
  [Work Queues](http://www.rabbitmq.com/tutorials/tutorial-two-elixir.html)
  RabbitMQ pattern.
  """
  use Lapin.Producer

  def confirm(%Producer{config: config}), do: Keyword.get(config, :confirm, true)

  def mandatory(%Producer{config: config}), do: Keyword.get(config, :mandatory, true)

  def persistent(%Producer{config: config}), do: Keyword.get(config, :persistent, true)
end
