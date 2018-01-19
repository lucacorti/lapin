defmodule Lapin.Pattern do
  @moduledoc """
  Extensible behaviour to define pattern modules.

  Lapin provides a number of submodules which impelment the patterns found in
  the [RabbitMQ Tutorials](http://www.rabbitmq.com/getstarted.html).

  ```
  defmodule ExampleApp.SomePatter do
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
  @callback consumer_ack(channel :: Channel.t()) :: boolean

  @doc """
  Consumer message prefetch count
  """
  @callback consumer_prefetch(channel :: Channel.t()) :: Channel.consumer_prefetch()

  @doc """
  Declare exchange type
  """
  @callback exchange_type(channel :: Channel.t()) :: boolean

  @doc """
  Declare exchange durable
  """
  @callback exchange_durable(channel :: Channel.t()) :: boolean

  @doc """
  Request publisher confirms (RabbitMQ only)
  """
  @callback publisher_confirm(channel :: Channel.t()) :: boolean

  @doc """
  Request message persistence when publishing
  """
  @callback publisher_persistent(channel :: Channel.t()) :: boolean

  @doc """
  Request message mandatory routing when publishing
  """
  @callback publisher_mandatory(channel :: Channel.t()) :: boolean

  @doc """
  Declare queue arguments
  """
  @callback queue_arguments(channel :: Channel.t()) :: Channel.queue_arguments()

  @doc """
  Declare queue durable
  """
  @callback queue_durable(channel :: Channel.t()) :: boolean

  @doc """
  Bind queue to routing_key
  """
  @callback routing_key(channel :: Channel.t()) :: Channel.routing_key()

  defmacro __using__([]) do
    quote do
      alias Lapin.Channel

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

      def consumer_ack(%Channel{config: config}),
        do: Keyword.get(config, :consumer_ack, @consumer_ack)

      def consumer_prefetch(%Channel{config: config}),
        do: Keyword.get(config, :consumer_prefetch, @consumer_prefetch)

      def exchange_durable(%Channel{config: config}),
        do: Keyword.get(config, :exchange_durable, @exchange_durable)

      def exchange_type(%Channel{config: config}),
        do: Keyword.get(config, :exchange_type, @exchange_type)

      def publisher_confirm(%Channel{config: config}),
        do: Keyword.get(config, :publisher_confirm, @publisher_confirm)

      def publisher_mandatory(%Channel{config: config}),
        do: Keyword.get(config, :publisher_mandatory, @publisher_mandatory)

      def publisher_persistent(%Channel{config: config}),
        do: Keyword.get(config, :publisher_persistent, @publisher_persistent)

      def queue_arguments(%Channel{config: config}),
        do: Keyword.get(config, :queue_arguments, @queue_arguments)

      def queue_durable(%Channel{config: config}),
        do: Keyword.get(config, :queue_durable, @queue_durable)

      def routing_key(%Channel{config: config}),
        do: Keyword.get(config, :routing_key, @routing_key)

      defoverridable Lapin.Pattern
    end
  end
end
