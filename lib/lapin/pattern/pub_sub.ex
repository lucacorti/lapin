defmodule Lapin.Pattern.PubSub do
  use Lapin.Pattern

  def exchange_type(channel_config), do: Keyword.get(channel_config, :exchange_type, :fanout)
end
