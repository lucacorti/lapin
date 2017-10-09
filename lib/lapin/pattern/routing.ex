defmodule Lapin.Pattern.Routing do
  use Lapin.Pattern

  def exchange_type(channel_config), do: Keyword.get(channel_config, :exchange_type, :direct)
  def routing_key(channel_config), do: Keyword.get(channel_config, :routing_key, "")
end
