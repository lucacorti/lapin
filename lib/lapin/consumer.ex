defmodule Lapin.Consumer do
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

  alias AMQP.{Basic, Channel, Connection}
  alias Lapin.Queue
  require Logger

  @typedoc "Consumer Tag"
  @type consumer_tag :: String.t()

  @typedoc "Consumer configuration"
  @type config :: Keyword.t()

  @typedoc "Consumer Prefetch"
  @type prefetch_count :: Integer.t()

  @doc """
  Consumer acknowledgements enabled
  """
  @callback ack(consumer :: t()) :: boolean

  @doc """
  Consumer message prefetch count
  """
  @callback prefetch_count(consumer :: t()) :: prefetch_count()

  @doc """
  Declare queue
  """
  @callback queue(consumer :: t()) :: Queue.t()

  defmacro __using__([]) do
    quote do
      alias Lapin.Consumer

      @behaviour Lapin.Consumer

      @ack false
      @queue_arguments []
      @queue_durable true

      def ack(%Consumer{config: config}), do: Keyword.get(config, :ack, @ack)

      def prefetch_count(%Consumer{config: config}), do: Keyword.get(config, :prefetch_count)

      def queue(%Consumer{config: config}), do: Keyword.get(config, :queue)

      def queue_arguments(%Consumer{config: config}),
        do: Keyword.get(config, :queue_arguments, @queue_arguments)

      def queue_durable(%Consumer{config: config}),
        do: Keyword.get(config, :queue_durable, @queue_durable)

      defoverridable Lapin.Consumer
    end
  end

  @typedoc "Lapin Consumer Behaviour"
  @type t :: %__MODULE__{
          channel: Channel,
          consumer_tag: consumer_tag(),
          pattern: atom,
          config: config(),
          queue: Queue.t()
        }
  defstruct channel: nil,
            consumer_tag: nil,
            pattern: nil,
            config: nil,
            queue: nil

  @doc """
  Creates a consumer from configuration
  """
  @spec create(connection :: Connection.t(), config) :: t
  def create(connection, config) do
    pattern = Keyword.get(config, :pattern, Lapin.Pattern.Config)
    consumer = %__MODULE__{config: config, pattern: pattern}

    with {:ok, channel} <- Channel.open(connection),
         consumer <- %{consumer | channel: channel},
         queue <- Queue.new(pattern.queue(consumer)),
         :ok <- Queue.declare(queue, channel),
         consumer <- %{consumer | queue: queue},
         :ok <- set_prefetch_count(consumer, pattern.prefetch_count(consumer)),
         {:ok, consumer_tag} <- consume(consumer, queue.name) do
      Logger.debug(fn -> "Channel setup complete" end)
      %{consumer | consumer_tag: consumer_tag}
    else
      {:error, error} ->
        Logger.error("Error creating consumer from config #{config}: #{inspect(error)}")
        consumer
    end
  end

  @doc """
  Find consumer by consumer_tag
  """
  @spec get([t], consumer_tag) :: t | nil
  def get(consumers, consumer_tag) do
    Enum.find(consumers, &(&1.consumer_tag == consumer_tag))
  end

  defp consume(_consumer, nil = _queue), do: {:ok, nil}

  defp consume(%{channel: channel, pattern: pattern} = consumer, queue) do
    Basic.consume(channel, queue, nil, no_ack: not pattern.ack(consumer))
  end

  defp set_prefetch_count(_consumer, nil = _prefetch_count), do: :ok

  defp set_prefetch_count(%{channel: channel}, prefetch_count) do
    Basic.qos(channel, prefetch_count: prefetch_count)
  end
end
