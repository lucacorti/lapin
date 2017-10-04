defmodule Lapin.Pattern do
  @moduledoc """
  Lapin Pattern behaviour

  Extensible behaviour to define Lapin Pattern modules. To configure your channels
  you can use the builtin Lapin.Pattern.* modules, extend any of them or extend
  Lapin.Pattern directly to define your custom RabbitMQ integration pattern and
  specify it in your channel configuration under the :pattern key.

  Please note that Lapin.Pattern mostly reads values from the configuration and
  tries to provide sensible defaults when configuration is missing, so you can
  just use the static configuration if you do not need dynamic behaviour.
  """

  @type channel_config :: Keyword.t
  @type consumer_tag :: String.t
  @type exchange :: String.t
  @type queue :: String.t
  @type error :: {:error, message :: String.t}
  @type queue_arguments :: [{String.t, atom, String.t}]

  @callback consumer_ack(channel_config) :: boolean
  @callback consumer_prefetch(channel_config) :: Integer.t | nil

  @callback exchange_type(channel_config) :: boolean
  @callback exchange_durable(channel_config) :: boolean

  @callback publisher_confirm(channel_config) :: boolean
  @callback publisher_persistent(channel_config) :: boolean
  @callback publisher_mandatory(channel_config) :: boolean

  @callback queue_arguments(channel_config) :: queue_arguments
  @callback queue_durable(channel_config) :: boolean

  @callback handle_cancel(channel_config) :: :ok | error
  @callback handle_cancel_ok(channel_config) :: :ok | error
  @callback handle_consume(channel_config, meta :: map , payload :: binary) :: :ok | error
  @callback handle_register(channel_config) :: :ok | error
  @callback handle_publish(channel_config, payload :: binary) :: :ok | error
  @callback handle_return(channel_config, meta :: map, payload :: binary) :: :ok | error

  defmacro __using__([]) do
    quote do
      @behaviour Lapin.Pattern

      @consumer_ack true
      @consumer_prefetch nil
      @exchange_type :direct
      @exchange_durable true
      @publisher_confirm false
      @publisher_mandatory false
      @publisher_persistent true
      @queue_arguments []
      @queue_durable true
      @routing_key ""

      def consumer_ack(channel_config), do: Keyword.get(channel_config, :consumer_ack, @consumer_ack)
      def consumer_prefetch(channel_config), do: Keyword.get(channel_config, :consumer_prefetch, @consumer_prefetch)
      def exchange_type(channel_config), do: Keyword.get(channel_config, :exchange_type, @exchange_type)
      def exchange_durable(channel_config), do: Keyword.get(channel_config, :exchange_durable, @exchange_durable)
      def handle_cancel(_channel_config), do: :ok
      def handle_cancel_ok(_channel_config), do: :ok
      def handle_consume(_channel_config, _meta, _payload), do: :ok
      def handle_publish(_channel_config, _message), do: :ok
      def handle_register(_channel_config), do: :ok
      def publisher_confirm(channel_config), do: Keyword.get(channel_config, :publisher_confirm, @publisher_confirm)
      def publisher_mandatory(channel_config), do: Keyword.get(channel_config, :publisher_mandatory, @publisher_mandatory)
      def publisher_persistent(channel_config), do: Keyword.get(channel_config, :publisher_persistent, @publisher_persistent)
      def queue_arguments(channel_config), do: Keyword.get(channel_config, :queue_arguments, @queue_arguments)
      def queue_durable(channel_config), do: Keyword.get(channel_config, :queue_durable, @queue_durable)
      def routing_key(channel_config), do: Keyword.get(channel_config, :routing_key, @routing_key)

      defoverridable [consumer_ack: 1, consumer_prefetch: 1, exchange_type: 1,
                      exchange_durable: 1, handle_cancel: 1, handle_cancel_ok: 1,
                      handle_consume: 3, handle_publish: 2, handle_register: 1,
                      publisher_confirm: 1, publisher_mandatory: 1,
                      publisher_persistent: 1, queue_arguments: 1,
                      queue_durable: 1, routing_key: 1]
    end
  end
end
