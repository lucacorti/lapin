defmodule Lapin.Channel do
  @moduledoc """
  Lapin Channel handling
  """

  require Logger

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
  @type consumer_prefetch :: Integer.t() | nil

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
          amqp_channel: AMQP.Channel,
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
  @spec create(connection :: AMQP.Connection.t(), config) :: t
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
           declare_exchange(amqp_channel, exchange, exchange_type, durable: exchange_durable),
         {:ok, _info} <-
           AMQP.Queue.declare(
             amqp_channel,
             queue,
             durable: queue_durable,
             arguments: queue_arguments
           ),
         :ok <- bind_to_exchange(amqp_channel, queue, exchange, routing_key: routing_key),
         {:ok, channel} <-
           setup(%{
             channel
             | amqp_channel: amqp_channel,
               pattern: pattern,
               routing_key: routing_key
           }) do
      channel
    else
      {:error, :missing_params, missing_params} ->
        params = Enum.join(missing_params, ", ")

        error =
          "Error creating channel from config #{inspect(config)}: missing mandatory params: #{
            params
          }"

        Logger.error(error)
        {:error, error}

      {:error, error} ->
        Logger.error("Error creating channel from config #{config}: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Find channel by consumer_tag
  """
  @spec get([t], consumer_tag) :: t
  def get(channels, consumer_tag) do
    Enum.find(channels, &channel_matches?(&1, consumer_tag))
  end

  @doc """
  Find channel by exchange and routing key
  """
  @spec get([t], exchange, routing_key, role) :: t
  def get(channels, exchange, routing_key, role) do
    Enum.find(channels, &channel_matches?(&1, exchange, routing_key, role))
  end

  defp setup(
         %{role: :consumer, amqp_channel: amqp_channel, pattern: pattern, queue: queue} = channel
       ) do
    with consumer_prefetch <- pattern.consumer_prefetch(channel),
         consumer_ack <- pattern.consumer_ack(channel),
         :ok <- set_consumer_prefetch(amqp_channel, consumer_prefetch),
         {:ok, consumer_tag} =
           AMQP.Basic.consume(amqp_channel, queue, nil, no_ack: not consumer_ack),
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
    AMQP.Basic.qos(amqp_channel, prefetch_count: consumer_prefetch)
  end

  defp set_publisher_confirm(_amqp_channel, false = _publisher_confirm), do: :ok

  defp set_publisher_confirm(amqp_channel, true = _publisher_confirm) do
    with :ok <- AMQP.Confirm.select(amqp_channel),
         :ok <- AMQP.Basic.return(amqp_channel, self()) do
      :ok
    else
      error ->
        error
    end
  end

  defp declare_exchange(_channel, nil = _exchange, _exchange_type, _options), do: :ok

  defp declare_exchange(_channel, "" = _exchange, _exchange_type, _options), do: :ok

  defp declare_exchange(channel, exchange, exchange_type, options) do
    AMQP.Exchange.declare(channel, exchange, exchange_type, options)
  end

  defp bind_to_exchange(_channel, _queue, nil = _exchange, _options), do: :ok

  defp bind_to_exchange(_channel, _queue, "" = _exchange, _options), do: :ok

  defp bind_to_exchange(channel, queue, exchange, options) do
    AMQP.Queue.bind(channel, queue, exchange, options)
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
