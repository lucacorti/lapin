defmodule Lapin.Channel do
  @moduledoc """
  Lapin Channel handling
  """

  require Logger

  alias AMQP.{Basic, Confirm}
  alias Lapin.Message

  import Lapin.Utils, only: [check_mandatory_params: 2]

  @typedoc "Channel role"
  @type role :: :consumer | :producer | :passive

  @typedoc "Exchange name"
  @type exchange :: String.t()

  @typedoc "Queue name"
  @type queue :: String.t()

  @typedoc "Routing key"
  @type routing_key :: String.t()

  @typedoc "Queue Arguments"
  @type queue_arguments :: [{String.t(), atom, String.t()}]

  @typedoc "Consumer Tag"
  @type consumer_tag :: String.t()

  @typedoc "Consumer Prefetch"
  @type consumer_prefetch :: integer() | nil

  @typedoc """
  Channel configuration

  The following keys are supported:
    - role: channel role (`atom`), allowed values are:
      - `:consumer`: Receives messages from the channel via `Lapin.Connection` callbacks
      - `:producer`: Can publish messages to che channel
      - `:passive`: Used to declare channel configuration, can't receive nor publish
    - pattern: channel pattern (module using the `Lapin.Pattern` behaviour)
    - exchange: broker exchange (`String.t`)
    - queue: broker queue (`String.t`)

  If using the `Lapin.Pattern.Config` default implementation, the following keys are also supported:
    - consumer_ack: send consumer ack (boolean), *default: false*
    - consumer_prefetch cosumer prefetch (integer | nil), *default: nil*
    - exchange_type: declare type of the exchange (:direct, :fanout, :topic), *default: :direct*
    - exchange_durable: declare exchange as durable (boolean), *default: true*
    - publisher_confirm: expect RabbitMQ publish confirms (boolean), *default: false*
    - publisher_mandatory: messages published as mandatory by default (boolean), *deafault: false*
    - publisher_persistent: messages published as persistent by default (boolean), *deafault: false*
    - queue_arguments: queue arguments (list of {string, type, value}), *default: []*
    - queue_durable: declare queue as durable (boolean), *default: true*
    - routing_key: routing_key for bindings (string), *default: ""*
  """
  @type config :: Keyword.t()

  @type t :: %__MODULE__{
          amqp_channel: AMQP.Channel.t(),
          consumer_tag: consumer_tag,
          pattern: Lapin.Pattern.t(),
          role: role,
          exchange: exchange,
          queue: queue,
          routing_key: routing_key,
          config: config
        }
  defstruct amqp_channel: nil,
            consumer_tag: nil,
            pattern: nil,
            role: :passive,
            exchange: "",
            queue: "",
            routing_key: "",
            config: nil

  @doc """
  Creates a channel from configuration
  """
  @spec create(connection :: AMQP.Connection.t(), config) :: {:ok, t} | {:error, term}
  def create(connection, config) do
    with :ok <- check_mandatory_params(config, [:role, :exchange, :queue]),
         role when not is_nil(role) <- Keyword.get(config, :role),
         exchange when not is_nil(exchange) <- Keyword.get(config, :exchange),
         queue when not is_nil(queue) <- Keyword.get(config, :queue),
         pattern <- Keyword.get(config, :pattern, Lapin.Pattern.Config),
         channel <- %__MODULE__{
           role: role,
           exchange: exchange,
           queue: queue,
           pattern: pattern,
           config: config
         },
         routing_key <- pattern.routing_key(channel),
         exchange_type <- pattern.exchange_type(channel),
         exchange_durable <- pattern.exchange_durable(channel),
         queue_arguments <- pattern.queue_arguments(channel),
         queue_durable <- pattern.queue_durable(channel),
         {:ok, amqp_channel} <- AMQP.Channel.open(connection),
         :ok <-
           AMQP.Exchange.declare(amqp_channel, exchange, exchange_type, durable: exchange_durable),
         {:ok, _info} <-
           AMQP.Queue.declare(
             amqp_channel,
             queue,
             durable: queue_durable,
             arguments: queue_arguments
           ),
         :ok <- AMQP.Queue.bind(amqp_channel, queue, exchange, routing_key: routing_key),
         {:ok, channel} <-
           setup(%{
             channel
             | amqp_channel: amqp_channel,
               pattern: pattern,
               routing_key: routing_key
           }) do
      {:ok, channel}
    else
      {:error, :missing_params, missing_params} ->
        params = Enum.join(missing_params, ", ")

        Logger.error(
          "Error creating channel config #{inspect(config, pretty: true)}: missing params: #{
            params
          }"
        )

        {:error, :missing_params}

      {:error, error} ->
        Logger.error(
          "Error creating channel from config #{inspect(config, pretty: true)}: #{inspect(error)}"
        )

        {:error, error}
    end
  end

  @doc """
  Find channel by consumer_tag
  """
  @spec get([t], consumer_tag) :: {:ok, t} | {:error, :channel_not_found}
  def get(channels, consumer_tag) do
    case Enum.find(channels, &channel_matches?(&1, consumer_tag)) do
      nil ->
        {:error, :channel_not_found}

      channel ->
        {:ok, channel}
    end
  end

  @doc """
  Find channel by exchange and routing key
  """
  @spec get([t], exchange, routing_key, role) :: {:ok, t} | {:error, :channel_not_found}
  def get(channels, exchange, routing_key, role) do
    case Enum.find(channels, &channel_matches?(&1, exchange, routing_key, role)) do
      nil ->
        {:error, :channel_not_found}

      channel ->
        {:ok, channel}
    end
  end

  @doc """
  Reject message
  """
  @spec reject(t, integer, boolean()) :: :ok | {:error, term}
  def reject(%{amqp_channel: amqp_channel}, delivery_tag, requeue) do
    with :ok <- Basic.reject(amqp_channel, delivery_tag, requeue: requeue) do
      Logger.debug("#{if requeue, do: "Requeued", else: "Rejected"} message #{delivery_tag}")
    else
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
  Publish message
  """
  @spec publish(t, exchange, routing_key, Message.payload(), Keyword.t()) :: :ok | {:error, term}
  def publish(%{amqp_channel: amqp_channel}, exchange, routing_key, payload, options) do
    Basic.publish(amqp_channel, exchange, routing_key, payload, options)
  end

  @doc """
  Wait for publish confirmation
  """
  @spec confirm(t) :: boolean()
  def confirm(%{amqp_channel: amqp_channel}) do
    case Confirm.wait_for_confirms(amqp_channel) do
      true -> true
      _ -> false
    end
  end

  @doc """
  ACK message consumption
  """
  @spec ack(t, integer) :: :ok | {:error, term}
  def ack(%{amqp_channel: amqp_channel}, delivery_tag) do
    Basic.ack(amqp_channel, delivery_tag)
  end

  defp setup(
         %{role: :consumer, amqp_channel: amqp_channel, pattern: pattern, queue: queue} = channel
       ) do
    with consumer_prefetch <- pattern.consumer_prefetch(channel),
         consumer_ack <- pattern.consumer_ack(channel),
         :ok <- set_consumer_prefetch(amqp_channel, consumer_prefetch),
         {:ok, consumer_tag} = Basic.consume(amqp_channel, queue, nil, no_ack: not consumer_ack),
         channel <- %{channel | consumer_tag: consumer_tag} do
      Logger.debug(fn -> "Consumer '#{consumer_tag}' bound to queue '#{queue}'" end)
      {:ok, channel}
    else
      error ->
        error
    end
  end

  defp setup(%{role: :producer, amqp_channel: amqp_channel, pattern: pattern} = channel) do
    with publisher_confirm <- pattern.publisher_confirm(channel),
         :ok <- set_publisher_confirm(amqp_channel, publisher_confirm) do
      {:ok, channel}
    else
      error ->
        error
    end
  end

  defp setup(%{role: :passive} = channel) do
    {:ok, channel}
  end

  defp set_consumer_prefetch(_amqp_channel, nil = _consumer_prefetch), do: :ok

  defp set_consumer_prefetch(amqp_channel, consumer_prefetch) do
    Basic.qos(amqp_channel, prefetch_count: consumer_prefetch)
  end

  defp set_publisher_confirm(_amqp_channel, false = _publisher_confirm), do: :ok

  defp set_publisher_confirm(amqp_channel, true = _publisher_confirm) do
    with :ok <- Confirm.select(amqp_channel),
         :ok <- Basic.return(amqp_channel, self()) do
      :ok
    else
      error ->
        error
    end
  end

  defp channel_matches?(channel, consumer_tag) do
    channel.consumer_tag == consumer_tag
  end

  defp channel_matches?(%{pattern: pattern} = channel, exchange, routing_key, role) do
    if pattern.exchange_type(channel) == :topic do
      channel.exchange == exchange && channel.role
    else
      channel.exchange == exchange && channel.routing_key == routing_key && channel.role == role
    end
  end
end
