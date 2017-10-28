defmodule Lapin.Pattern do
  @moduledoc """
  Extensible behaviour to define pattern modules.

  Lapin provides a number of submodules which impelment the patterns found in
  the [RabbitMQ Tutorials](http://www.rabbitmq.com/getstarted.html).

  ```
  defmodule MyApp.SomePatter do
    use Lapin.Pattern

    [... callbacks implementation ...]
  end
  ```
  """

  alias Lapin.Channel

  @typedoc "Lapin Pattern Behaviour"
  @type t :: __MODULE__

  @doc """
  Consumer acknowledgements enabled
  """
  @callback consumer_ack(channel_config :: Channel.config) :: boolean

  @doc """
  Consumer message prefetch count
  """
  @callback consumer_prefetch(channel_config :: Channel.config) :: Channel.consumer_prefetch

  @doc """
  Declare exchange type
  """
  @callback exchange_type(channel_config :: Channel.config) :: boolean

  @doc """
  Declare exchange durable
  """
  @callback exchange_durable(channel_config :: Channel.config) :: boolean

  @doc """
  Request publisher confirms (RabbitMQ only)
  """
  @callback publisher_confirm(channel_config :: Channel.config) :: boolean

  @doc """
  Request message persistence when publishing
  """
  @callback publisher_persistent(channel_config :: Channel.config) :: boolean

  @doc """
  Request message mandatory routing when publishing
  """
  @callback publisher_mandatory(channel_config :: Channel.config) :: boolean

  @doc """
  Declare queue arguments
  """
  @callback queue_arguments(channel_config :: Channel.config) :: Channel.queue_arguments

  @doc """
  Declare queue durable
  """
  @callback queue_durable(channel_config :: Channel.config) :: boolean

  @doc """
  Bind queue to routing_key
  """
  @callback routing_key(channel_config :: Channel.config) :: Channel.routing_key

  defmacro __using__([]) do
    quote do
      @behaviour Lapin.Pattern

      @consumer_ack false
      @consumer_prefetch nil
      @exchange_durable true
      @exchange_type :direct
      @publisher_confirm false
      @publisher_mandatory false
      @publisher_persistent false
      @queue_arguments []
      @queue_durable true
      @routing_key ""

      def consumer_ack(channel_config), do: Keyword.get(channel_config, :consumer_ack, @consumer_ack)
      def consumer_prefetch(channel_config), do: Keyword.get(channel_config, :consumer_prefetch, @consumer_prefetch)
      def exchange_durable(channel_config), do: Keyword.get(channel_config, :exchange_durable, @exchange_durable)
      def exchange_type(channel_config), do: Keyword.get(channel_config, :exchange_type, @exchange_type)
      def publisher_confirm(channel_config), do: Keyword.get(channel_config, :publisher_confirm, @publisher_confirm)
      def publisher_mandatory(channel_config), do: Keyword.get(channel_config, :publisher_mandatory, @publisher_mandatory)
      def publisher_persistent(channel_config), do: Keyword.get(channel_config, :publisher_persistent, @publisher_persistent)
      def queue_arguments(channel_config), do: Keyword.get(channel_config, :queue_arguments, @queue_arguments)
      def queue_durable(channel_config), do: Keyword.get(channel_config, :queue_durable, @queue_durable)
      def routing_key(channel_config), do: Keyword.get(channel_config, :routing_key, @routing_key)

      defoverridable Lapin.Pattern
    end
  end
end
