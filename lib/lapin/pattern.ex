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

  alias Lapin.Connection

  @typedoc """
  Channel role
  """
  @type role :: :consumer | :producer | :passive

  @typedoc """
  Consumer Tag
  """
  @type consumer_tag :: String.t

  @typedoc """
  Exchange name
  """
  @type exchange :: String.t

  @typedoc """
  Queue name
  """
  @type queue :: String.t

  @typedoc """
  Queue Arguments
  """
  @type queue_arguments :: [{String.t, atom, String.t}]

  @typedoc """
  Consumer Prefetch
  """
  @type consumer_prefetch :: Integer.t | nil

  @typedoc """
  Routing key
  """
  @type routing_key :: String

  @doc """
  Consumer acknowledgements enabled
  """
  @callback consumer_ack(channel_config :: Connection.channel_config) :: boolean

  @doc """
  Consumer message prefetch count
  """
  @callback consumer_prefetch(channel_config :: Connection.channel_config) :: consumer_prefetch

  @doc """
  Declare exchange type
  """
  @callback exchange_type(channel_config :: Connection.channel_config) :: boolean

  @doc """
  Declare exchange durable
  """
  @callback exchange_durable(channel_config :: Connection.channel_config) :: boolean

  @doc """
  Request publisher confirms (RabbitMQ only)
  """
  @callback publisher_confirm(channel_config :: Connection.channel_config) :: boolean

  @doc """
  Request message persistence when publishing
  """
  @callback publisher_persistent(channel_config :: Connection.channel_config) :: boolean

  @doc """
  Request message mandatory routing when publishing
  """
  @callback publisher_mandatory(channel_config :: Connection.channel_config) :: boolean

  @doc """
  Declare queue arguments
  """
  @callback queue_arguments(channel_config :: Connection.channel_config) :: queue_arguments

  @doc """
  Declare queue durable
  """
  @callback queue_durable(channel_config :: Connection.channel_config) :: boolean

  @doc """
  Bind queue to routing_key
  """
  @callback routing_key(channel_config :: Connection.channel_config) :: routing_key

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

      defoverridable [consumer_ack: 1, consumer_prefetch: 1, exchange_type: 1,
                      exchange_durable: 1, publisher_confirm: 1,
                      publisher_mandatory: 1, publisher_persistent: 1,
                      queue_arguments: 1, queue_durable: 1, routing_key: 1]
    end
  end
end
