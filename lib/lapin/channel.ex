defmodule Lapin.Channel do
  @moduledoc """
  Lapin Channel handling
  """

  use AMQP

  require Logger

  import Lapin.Utils, only: [check_mandatory_params: 2]

  @typedoc "Channel role"
  @type role :: :consumer | :producer | :passive

  @typedoc "Exchange name"
  @type exchange :: String.t

  @typedoc "Queue name"
  @type queue :: String.t

  @typedoc "Routing key"
  @type routing_key :: String.t

  @typedoc "Queue Arguments"
  @type queue_arguments :: [{String.t, atom, String.t}]

  @typedoc "Consumer Tag"
  @type consumer_tag :: String.t

  @typedoc "Consumer Prefetch"
  @type consumer_prefetch :: Integer.t | nil

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
  @type config :: Keyword.t

  @spec create(connection :: Connection.t, config) :: config
  def create(connection, config) do
    with :ok <- check_mandatory_params(config, [:role, :exchange, :queue]),
         role when not is_nil(role) <- Keyword.get(config, :role),
         exchange when not is_nil(exchange) <- Keyword.get(config, :exchange),
         queue when not is_nil(queue) <- Keyword.get(config, :queue),
         pattern <- Keyword.get(config, :pattern, Lapin.Pattern.Config),
         exchange_type <- pattern.exchange_type(config),
         exchange_durable <- pattern.exchange_durable(config),
         queue_arguments <- pattern.queue_arguments(config),
         queue_durable <- pattern.queue_durable(config),
         routing_key <- pattern.routing_key(config),
         {:ok, channel} <- Channel.open(connection),
         config <- Keyword.merge(config, [pattern: pattern, channel: channel, routing_key: routing_key]),
         :ok <- Exchange.declare(channel, exchange, exchange_type, durable: exchange_durable),
         {:ok, _info} <- Queue.declare(channel, queue, durable: queue_durable, arguments: queue_arguments),
         :ok <- Queue.bind(channel, queue, exchange, routing_key: routing_key),
         {:ok, config} <- setup(config, role, channel, pattern, queue) do
      config
    else
      {:error, :missing_params, missing_params} ->
        params = Enum.join(missing_params, ", ")
        error = "Error creating channel #{inspect config}: missing mandatory params: #{params}"
        Logger.error error
        {:error, error}
      {:error, error} ->
        Logger.error "Error creating channel #{config}: #{inspect error}"
        {:error, error}
    end
  end

  @doc """
  Retrieve channel configuration by consumer_tag
  """
  @spec get_config([config], consumer_tag) :: config
  def get_config(channels, consumer_tag) do
    Enum.find(channels, fn config ->
      consumer_tag == Keyword.get(config, :consumer_tag)
    end)
  end


  @doc """
  Retrieve channel configuration by exchange and routing_key
  """
  @spec get_config([config], exchange, routing_key) :: config
  def get_config(channels, exchange, routing_key) do
    Enum.find(channels, fn config ->
      exchange == Keyword.get(config, :exchange) && routing_key == Keyword.get(config, :routing_key)
    end)
  end

  defp setup(config, :consumer, channel, pattern, queue) do
    with consumer_prefetch <- pattern.consumer_prefetch(config),
         consumer_ack <- pattern.consumer_ack(config),
         :ok <- set_consumer_prefetch(channel, consumer_prefetch),
         {:ok, consumer_tag} = Basic.consume(channel, queue, nil, no_ack: not consumer_ack),
         config <- Keyword.put(config, :consumer_tag, consumer_tag) do
      Logger.debug fn -> "Consumer '#{consumer_tag}' bound to queue '#{queue}'" end
      {:ok, config}
    else
      error ->
        error
    end
  end

  defp setup(config, :producer, channel, pattern, _queue) do
    with publisher_confirm <- pattern.publisher_confirm(config),
         :ok <- set_publisher_confirm(channel, publisher_confirm) do
      {:ok, config}
    else
      error ->
        error
    end
  end

  defp setup(config, :passive, _channel, _pattern, _queue) do
    {:ok, config}
  end

  defp set_consumer_prefetch(_channel, nil = _consumer_prefetch), do: :ok
  defp set_consumer_prefetch(channel, consumer_prefetch) do
    Basic.qos(channel, prefetch_count: consumer_prefetch)
  end

  defp set_publisher_confirm(_channel, false = _publisher_confirm), do: :ok
  defp set_publisher_confirm(channel, true = _publisher_confirm) do
    with :ok <- Confirm.select(channel),
         :ok <- Basic.return(channel, self()) do
      :ok
    else
      error ->
        error
    end
  end
end
