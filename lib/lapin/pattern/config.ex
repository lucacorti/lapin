defmodule Lapin.Pattern.Config do
  @moduledoc """
  Default `Lapin.Pattern` behaviour implementation for workers

  Used by default to read settings from the static configuration file and
  provide defaults for unspecified settings.
  """
  use Lapin.Pattern

  @consumer_ack false
  @consumer_prefetch nil
  @exchange_type :direct
  @exchange_durable true
  @publisher_confirm false
  @publisher_mandatory false
  @publisher_persistent false
  @queue_arguments []
  @queue_durable true
  @routing_key ""

  def consumer_ack(channel_config), do: Keyword.get(channel_config, :consumer_ack, @consumer_ack)
  def consumer_prefetch(channel_config), do: Keyword.get(channel_config, :consumer_prefetch, @consumer_prefetch)
  def exchange_type(channel_config), do: Keyword.get(channel_config, :exchange_type, @exchange_type)
  def exchange_durable(channel_config), do: Keyword.get(channel_config, :exchange_durable, @exchange_durable)
  def publisher_confirm(channel_config), do: Keyword.get(channel_config, :publisher_confirm, @publisher_confirm)
  def publisher_mandatory(channel_config), do: Keyword.get(channel_config, :publisher_mandatory, @publisher_mandatory)
  def publisher_persistent(channel_config), do: Keyword.get(channel_config, :publisher_persistent, @publisher_persistent)
  def queue_arguments(channel_config), do: Keyword.get(channel_config, :queue_arguments, @queue_arguments)
  def queue_durable(channel_config), do: Keyword.get(channel_config, :queue_durable, @queue_durable)
  def routing_key(channel_config), do: Keyword.get(channel_config, :routing_key, @routing_key)
end
