defmodule Lapin.Consumer do
  @moduledoc """
  Extensible behaviour to define consumer configuration.

  Lapin provides a number of submodules which implement the patterns found in
  the [RabbitMQ Tutorials](http://www.rabbitmq.com/getstarted.html).

  ```
  defmodule ExampleApp.SomePatter do
    use Lapin.Pattern

    [... callbacks implementation ...]
  end
  ```
  """

  require Logger

  alias AMQP.{Basic, Channel, Connection}
  alias Lapin.Queue

  @typedoc "Consumer Tag"
  @type consumer_tag :: String.t()

  @typedoc """
  Consumer configuration

  The following keys are supported:
    - pattern: producer pattern (module using the `Lapin.Producer` behaviour)

  If using the `Lapin.Consumer.Config` default implementation, the following keys are also supported:
    - queue: queue to consume from, (`String.t()`, *required*)
    - ack: producer ack (`boolean()`, default: false*
    - prefetch_count: consumer prefetch count (`integer()`, *default: 1*)
  """
  @type config :: Keyword.t()

  @typedoc "Consumer Prefetch"
  @type prefetch_count :: integer

  @doc """
  Consumer acknowledgements enabled
  """
  @callback ack(consumer :: t()) :: boolean

  @doc """
  Consumer message prefetch count
  """
  @callback prefetch_count(consumer :: t()) :: prefetch_count()

  @doc """
  Queue to consume from
  """
  @callback queue(consumer :: t()) :: Queue.t()

  defmacro __using__([]) do
    quote do
      alias Lapin.Consumer

      @behaviour Consumer

      def ack(%Consumer{config: config}), do: Keyword.get(config, :ack, false)
      def prefetch_count(%Consumer{config: config}), do: Keyword.get(config, :prefetch_count, 1)
      def queue(%Consumer{config: config}), do: Keyword.fetch!(config, :queue)

      defoverridable Consumer
    end
  end

  @typedoc "Lapin Consumer Behaviour"
  @type t :: %__MODULE__{
          channel: Channel.t(),
          consumer_tag: consumer_tag(),
          pattern: atom,
          config: config(),
          queue: String.t()
        }
  defstruct channel: nil,
            consumer_tag: nil,
            pattern: nil,
            config: nil,
            queue: nil

  @doc """
  Creates a consumer from configuration
  """
  @spec create(Connection.t(), config) :: t
  def create(connection, config) do
    pattern = Keyword.get(config, :pattern, Lapin.Consumer.Config)
    consumer = %__MODULE__{config: config, pattern: pattern}

    with {:ok, channel} <- Channel.open(connection),
         consumer <- %{consumer | channel: channel},
         queue <- pattern.queue(consumer),
         :ok <- set_prefetch_count(consumer, pattern.prefetch_count(consumer)),
         {:ok, consumer_tag} <- consume(consumer, queue) do
      %{consumer | consumer_tag: consumer_tag, queue: queue}
    else
      {:error, error} ->
        Logger.error("Error creating consumer from config #{config}: #{inspect(error)}")
        consumer
    end
  end

  @doc """
  Find consumer by consumer_tag
  """
  @spec get([t], consumer_tag) :: {:ok, t} | {:error, :not_found}
  def get(consumers, consumer_tag) do
    case Enum.find(consumers, &(&1.consumer_tag == consumer_tag)) do
      nil -> {:error, :not_found}
      channel -> {:ok, channel}
    end
  end

  @doc """
  Reject message
  """
  @spec reject_message(t, integer, boolean()) :: :ok | {:error, term}
  def reject_message(%{channel: channel}, delivery_tag, requeue) do
    case Basic.reject(channel, delivery_tag, requeue: requeue) do
      :ok ->
        Logger.debug("#{if requeue, do: "Requeued", else: "Rejected"} message #{delivery_tag}")

      error ->
        Logger.error(
          "Error #{if requeue, do: "requeueing", else: "rejecting"} message #{delivery_tag}: #{
            inspect(error)
          }"
        )

        error
    end
  end

  @doc """
  ACK message consumption
  """
  @spec ack_message(t, integer) :: :ok | {:error, term}
  def ack_message(%{channel: channel}, delivery_tag) do
    Basic.ack(channel, delivery_tag)
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
