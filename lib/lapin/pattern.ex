defmodule Lapin.Pattern do
  @moduledoc """
  Extensible behaviour to define Lapin Pattern modules.

  To configure your channels you can use the builtin `Lapin.Pattern` submodules
  to define the various knobs needed to interact with the RabbitMQ broker.
  Lapin provides a number of modules which impelment the patterns found in the
  [RabbitMQ Tutorials](http://www.rabbitmq.com/getstarted.html).

  To define your custom RabbitMQ interaction pattern you can extend
  the `Lapin.Pattern` behaviour and redefining the relevant callbacks.

  Patterns are configured per channel in your channel configuration under
  the :pattern key. If not specified, it falls back to the `Lapin.Pattern`
  module, which tries to read most settings from the configuration and provides
  sensible defaults. You can just use the static configuration if you do not need
  to determine your `Lapin.Pattern` values dynamically at runtime.
  """

  alias Lapin.Worker

  @type consumer_tag :: String.t
  @type exchange :: String.t
  @type queue :: String.t
  @type queue_arguments :: [{String.t, atom, String.t}]
  @type prefetch :: Integer.t | nil
  @type routing_key :: String

  @callback consumer_ack(Worker.channel_config) :: boolean
  @callback consumer_prefetch(Worker.channel_config) :: prefetch

  @callback exchange_type(Worker.channel_config) :: boolean
  @callback exchange_durable(Worker.channel_config) :: boolean

  @callback publisher_confirm(Worker.channel_config) :: boolean
  @callback publisher_persistent(Worker.channel_config) :: boolean
  @callback publisher_mandatory(Worker.channel_config) :: boolean

  @callback queue_arguments(Worker.channel_config) :: queue_arguments
  @callback queue_durable(Worker.channel_config) :: boolean

  @callback routing_key(Worker.channel_config) :: routing_key

  defmacro __using__([]) do
    quote do
      @behaviour Lapin.Pattern

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

      defoverridable [consumer_ack: 1, consumer_prefetch: 1, exchange_type: 1,
                      exchange_durable: 1, publisher_confirm: 1,
                      publisher_mandatory: 1, publisher_persistent: 1,
                      queue_arguments: 1, queue_durable: 1, routing_key: 1]
    end
  end
end
