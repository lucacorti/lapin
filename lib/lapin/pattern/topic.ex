defmodule Lapin.Pattern.Topic do
  use Lapin.Pattern

  def exchange_type(channel_config), do: Keyword.get(channel_config, :exchange_type, :topic)
  def routing_key(channel_config), do: Keyword.get(channel_config, :routing_key, "")
end
