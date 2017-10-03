defmodule Lapin.Pattern.WorkerQueue do
  use Lapin.Pattern

  def consumer_prefetch(_channel_config), do: 1
  def publisher_confirm(_channel_config), do: true
  def routing_key(channel_config), do: Keyword.get(channel_config, :queue)
end
