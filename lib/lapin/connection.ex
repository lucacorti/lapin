defmodule Lapin.Connection do
  @moduledoc """
  RabbitMQ connection handler
  """
  use AMQP
  require Logger

  use GenServer

  alias Lapin.{Message, Worker}

  @typedoc """
  Connection
  """
  @type t :: GenServer.server

  @typedoc """
  Module conforming to `Lapin.Pattern`
  """
  @type pattern :: Lapin.Pattern

  @typedoc """
  Exchange name
  """
  @type exchange :: String.t

  @typedoc """
  Queue name
  """
  @type queue :: String.t

  @typedoc """
  Routing key
  """
  @type routing_key :: String.t

  @typedoc """
  Connection configuration

  The following keys are supported:
    - module: module adopting the `Lapin.Connection` behaviour
    - host: broker hostname (string | charlist), *default: 'localhost'*
    - port: broker port (string | integer), *default: 5672*
    - virtual_host: broker vhost (string), *default: ""*
    - username: username (string)
    - password: password (string)
    - auth_mechanisms: broker auth_mechanisms ([:amqplain | :external | :plain]), *default: amqp_client default*
    - ssl_options: ssl options ([:ssl:ssl_option]), *default: none*
    - channels: channels to configure ([channel_config]), *default: []*
  """
  @type config :: [channels: [channel_config]]

  @typedoc """
  Channel configuration

  The following keys are supported:
    - role: channel role (`atom`), allowed values are:
      - `:consumer`: Receives messages from the channel via `Lapin.Connection` callbacks
      - `:producer`: Can publish messages to che channel
      - `:passive`: Used to declare channel configuration, can't receive nor publish
    - pattern: channel pattern (module adopting the `Lapin.Pattern` behaviour)
    - exchange: broker exchange (`String.t`)
    - queue: broker queue (`String.t`)

  If using the default `Lapin.Pattern` implementation, the following keys are also supported:
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
  @type channel_config :: Keyword.t

  @typedoc """
  `Lapin.Connection` generic callback result
  """
  @type on_callback :: :ok | {:error, message :: String.t}

  @typedoc """
  Reason for message rejection
  """
  @type reason :: term

  @typedoc """
  `Lapin.Conenction` handle_deliver callback result
  """
  @type on_deliver :: :ok | {:reject, reason} | {:requeue, reason} | term

  @doc """
  Called when receiving a `basic.cancel` from the broker.
  """
  @callback handle_cancel(channel_config :: Connection.channel_config) :: on_callback

  @doc """
  Called when receiving a `basic.cancel_ok` from the broker.
  """
  @callback handle_cancel_ok(channel_config :: Connection.channel_config) :: on_callback

  @doc """
  Called when receiving a `basic.deliver` from the broker.

  Return values from this callback determine message acknowledgement:
    - `:ok`: Message was processed by the consumer and should be removed from queue
    - `{:requeue, reason}`: Message was not processed and should be requeued
    - `{:reject, reason}`: Message was not processed but should NOT be requeued

  Any other return value, including a crash in the callback code, has the same
  effect as `{:reject, reason}`: it rejects the message WITHOUT requeueing. The
  `reason` term can be used by the application to signal the reason of rejection
   and is logged in debug.
  """
  @callback handle_deliver(channel_config :: Connection.channel_config, message :: Message.t) :: on_deliver

  @doc """
  Called when receiving a `basic.consume_ok` from the broker.

  This signals successul registration as a consumer.
  """
  @callback handle_consume_ok(channel_config :: Connection.channel_config) :: on_callback

  @doc """
  Called when completing a `basic.publish` with the broker.

  Message transmission to the broker is successful when this callback is called.
  """
  @callback handle_publish(channel_config :: Connection.channel_config, message :: Message.t) :: on_callback

  @doc """
  Called when receiving a `basic.return` from the broker.

  THis signals an undeliverable returned message from the broker.
  """
  @callback handle_return(channel_config :: Connection.channel_config, message :: Message.t) :: on_callback

  defmacro __using__(_) do
    quote do
      alias Lapin.Connection, as: Conn
      alias Lapin.Message

      @behaviour Lapin.Connection

      def handle_cancel(_consumer_tag), do: :ok
      def handle_cancel_ok(_consumer_tag), do: :ok
      def handle_consume_ok(_channel_config), do: :ok
      def handle_deliver(_channel_config, _message), do: :ok
      def handle_publish(_channel_config, _message), do: :ok
      def handle_return(_channel_config, _message), do: :ok

      defoverridable Lapin.Connection

      def publish(exchange, routing_key, message, options \\ []) do
        Conn.publish(__MODULE__, exchange, routing_key, message, options)
      end

    end
  end

  @connection_mandatory_params [:module]
  @channel_mandatory_params [:role, :pattern, :exchange, :queue]
  @connection_default_params [connecion_timeout: 5_000]
  @default_rabbitmq_host 'localhost'
  @default_rabbitmq_port 5672
  @default_reconnection_delay 5_000

  @doc """
  Starts a `Lapin.Connection` with the specified configuration
  """
  @spec start_link(config, options :: GenServer.options) :: GenServer.on_start
  def start_link(configuration, options \\ []) do
    {:ok, configuration} = cleanup_configuration(configuration)
    GenServer.start_link(__MODULE__, configuration, options)
  end

  def init(configuration) do
    {:ok, connection, channels} = connect(configuration)
    {:ok, %{channels: channels, connection: connection, configuration: configuration}}
  end

  @doc """
  Closes the connection
  """
  @spec close(connection :: t) :: nil
  def close(connection), do: GenServer.stop(connection)

  @doc """
  Publishes a message to the specified exchange with the given routing_key
  """
  @spec publish(connection :: t, exchange, routing_key,
  message :: Message.t, options :: Keyword.t) :: Worker.on_callback
  def publish(connection, exchange, routing_key, message, options \\ []) do
    GenServer.call(connection, {:publish, exchange, routing_key, message, options})
  end

  def handle_call({:publish, exchange, routing_key, message, options}, _from,
  %{channels: channels, configuration: configuration} = state) do
    with module <- Keyword.get(configuration, :module),
         channel_config when not is_nil(channel_config) <- get_channel_config(channels, exchange, routing_key),
         :producer <- Keyword.get(channel_config, :role),
         channel when not is_nil(channel) <- Keyword.get(channel_config, :channel),
         pattern <- Keyword.get(channel_config, :pattern),
         mandatory <- pattern.publisher_mandatory(channel_config),
         persistent <- pattern.publisher_persistent(channel_config),
         options <- Keyword.merge([mandatory: mandatory, persistent: persistent], options),
         :ok <- Basic.publish(channel, exchange, routing_key, message.payload, options) do
      if not pattern.publisher_confirm(channel_config) or Confirm.wait_for_confirms(channel) do
          Logger.debug fn -> "Published to '#{exchange}'->'#{routing_key}': #{inspect message}" end
          {:reply, module.handle_publish(channel_config, message), state}
        else
          error = "Error publishing #{inspect message} to #{exchange}: broker did not confirm reception"
          Logger.debug fn -> error end
          {:reply, {:error, error}, state}
        end
    else
      :passive ->
        error = "Cannot publish, channel role is :passive"
        Logger.error error
        {:reply, {:error, error}, state}
      :consumer ->
        error = "Cannot publish, channel role is :consumer"
        Logger.error error
        {:reply, {:error, error}, state}
      nil ->
        error = "Error publishing message: no channel for '#{exchange}'->'#{routing_key}'"
        Logger.debug fn -> error end
        {:reply, {:error, error}, state}
      {:error, error} ->
        Logger.debug fn -> "Error sending message: #{inspect error}" end
        {:reply, {:error, error}, state}
    end
  end

  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}},
  %{channels: channels, configuration: configuration} = state) do
    with module <- Keyword.get(configuration, :module),
         channel_config when not is_nil(channel_config) <- get_channel_config(channels, consumer_tag),
         :ok <- module.handle_cancel(consumer_tag) do
        Logger.debug fn -> "Broker cancelled consumer_tag '#{consumer_tag}' for channel #{inspect channel_config}" end
    else
      nil ->
        Logger.warn "Broker cancelled consumer_tag '#{consumer_tag}' for locally unknown channel"
      {:error, error} ->
        Logger.error "Error canceling consumer_tag '#{consumer_tag}': #{error}"
    end
    {:stop, :normal, state}
  end

  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}},
  %{channels: channels, configuration: configuration} = state) do
    with module <- Keyword.get(configuration, :module),
         channel_config when not is_nil(channel_config) <- get_channel_config(channels, consumer_tag),
         :ok <- module.handle_cancel_ok(consumer_tag) do
      Logger.debug fn -> "Broker confirmed cancel consumer_tag '#{consumer_tag}' for channel #{inspect channel_config}" end
    else
      nil ->
        Logger.debug fn -> "Broker confirmed cancel for consumer_tag '#{consumer_tag}' for locally unknown channel" end
      {:error, error} ->
        Logger.error "Error confirming cancel for consumer_tag '#{consumer_tag}': #{error}"
    end
    {:noreply, state}
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}},
  %{channels: channels, configuration: configuration} = state) do
    with module <- Keyword.get(configuration, :module),
         channel_config when not is_nil(channel_config) <- get_channel_config(channels, consumer_tag),
         :ok <- module.handle_consume_ok(consumer_tag) do
        Logger.debug fn -> "Broker registered consumer_tag '#{consumer_tag}' for channel #{inspect channel_config}" end
    else
      nil ->
        Logger.warn "Broker registered consumer_tag '#{consumer_tag}', unknown channel"
      {:error, error} ->
        Logger.error "Broker error registration callback: #{error}"
    end
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, %{consumer_tag: consumer_tag} = meta},
  %{channels: channels, configuration: configuration} = state) do
    with module <- Keyword.get(configuration, :module),
         channel_config when not is_nil(channel_config) <- get_channel_config(channels, consumer_tag),
         channel when not is_nil(channel) <- Keyword.get(channel_config, :channel),
         message <- %Message{meta: meta, payload: payload} do
      spawn(fn ->
        consume(module, channel, channel_config, message)
      end)
    else
      nil ->
        Logger.error "Error processing message #{meta.delivery_tag}, unknown channel"
    end
    {:noreply, state}
  end

  def handle_info({:basic_return, payload, %{exchange: exchange, routing_key: routing_key} = meta},
  %{channels: channels, configuration: configuration} = state) do
    with module <- Keyword.get(configuration, :module),
         channel_config when not is_nil(channel_config) <- get_channel_config(channels, exchange, routing_key),
         :ok <- module.handle_return(channel_config, %Message{meta: meta, payload: payload}) do
      Logger.debug fn -> "Returned message for '#{exchange}'->'#{routing_key}': #{inspect meta}" end
    else
      error ->
        Logger.debug fn -> "Error handling returned message: #{inspect error}" end
    end
    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, _pid, _reason}, state) do
    Logger.warn "Connection down, restarting..."
    {:stop, :normal, state}
  end

  def handle_info(msg, state) do
     Logger.warn "MESSAGE: #{inspect msg}"
     {:noreply, state}
  end

  def terminate(_reason, %{connection: connection}) do
    Connection.close(connection)
  end

  defp consume(module, channel, channel_config, %Message{meta: %{delivery_tag: delivery_tag}} = message) do
    Logger.debug fn -> "Consuming message #{delivery_tag}" end

    with pattern = Keyword.get(channel_config, :pattern),
         consumer_ack <- pattern.consumer_ack(channel_config),
         :ok <- module.handle_deliver(channel_config, message) do
      consume_ack(consumer_ack, channel, delivery_tag)
     else
      {:reject, reason} ->
        Basic.reject(channel, delivery_tag, requeue: false)
        Logger.debug fn -> "Message #{delivery_tag} REJECTED, NOT REQUEUED: #{inspect reason}" end
      {:requeue, reason} ->
        Basic.reject(channel, delivery_tag, requeue: true)
        Logger.debug fn -> "Message #{delivery_tag} NOT CONSUMED, REQUEUED: #{inspect reason}" end
      error ->
        Basic.reject(channel, delivery_tag, requeue: false)
        Logger.debug fn -> "Message #{delivery_tag} INVALID RETURN VALUE, NOT REQUEUED: #{inspect error}" end
    end

    rescue
      exception ->
        Basic.reject(channel, delivery_tag, requeue: false)
        Logger.error "Message #{delivery_tag} CONSUMER CRASHED, NOT REQUEUED: #{inspect exception}"
  end

  defp consume_ack(true = _consumer_ack, channel, delivery_tag) do
    if Basic.ack(channel, delivery_tag) do
      Logger.debug fn -> "Message #{delivery_tag} consumed successfully, with ACK" end
      :ok
    else
      Logger.debug fn -> "Message #{delivery_tag} ACK failed" end
      :error
    end
  end

  defp consume_ack(false = _consumer_ack, _channel, delivery_tag) do
    Logger.debug fn -> "Message #{delivery_tag} consumed successfully, without ACK" end
    :ok
  end

  defp connect(configuration) do
    with {channels, configuration} <- Keyword.pop(configuration, :channels, []),
         configuration <- Keyword.merge(@connection_default_params, configuration),
         {:ok, connection} <- Connection.open(configuration) do
      Process.monitor(connection.pid)
      {:ok, connection, Enum.map(channels, &create_channel(connection, &1))}
    else
      {:error, _} ->
        :timer.sleep(@default_reconnection_delay)
        connect(configuration)
    end
  end

  defp create_channel(connection, channel_config) do
    with :ok <- check_mandatory_params(channel_config, @channel_mandatory_params),
         role when not is_nil(role) <- Keyword.get(channel_config, :role),
         exchange when not is_nil(exchange) <- Keyword.get(channel_config, :exchange),
         queue when not is_nil(queue) <- Keyword.get(channel_config, :queue),
         pattern <- Keyword.get(channel_config, :pattern, Lapin.Pattern.Config),
         exchange_type <- pattern.exchange_type(channel_config),
         exchange_durable <- pattern.exchange_durable(channel_config),
         queue_arguments <- pattern.queue_arguments(channel_config),
         queue_durable <- pattern.queue_durable(channel_config),
         routing_key <- pattern.routing_key(channel_config),
         {:ok, channel} <- Channel.open(connection),
         channel_config <- Keyword.merge(channel_config, [channel: channel, routing_key: routing_key]),
         :ok <- Exchange.declare(channel, exchange, exchange_type, durable: exchange_durable),
         {:ok, _info} <- Queue.declare(channel, queue, durable: queue_durable, arguments: queue_arguments),
         :ok <- Queue.bind(channel, queue, exchange, routing_key: routing_key),
         {:ok, channel_config} <- setup_channel(channel_config, role, channel, pattern, queue) do
      channel_config
    else
      {:error, :missing_params, missing_params} ->
        params = Enum.join(missing_params, ", ")
        error = "Error creating channel #{inspect channel_config}: missing mandatory params: #{params}"
        Logger.error error
        {:error, error}
      {:error, error} ->
        Logger.error "Error creating channel #{channel_config}: #{inspect error}"
        {:error, error}
    end
  end

  defp setup_channel(channel_config, :consumer, channel, pattern, queue) do
    with consumer_prefetch <- pattern.consumer_prefetch(channel_config),
         consumer_ack <- pattern.consumer_ack(channel_config),
         :ok <- setup_consumer_prefetch(channel, consumer_prefetch),
         {:ok, consumer_tag} = Basic.consume(channel, queue, nil, no_ack: not consumer_ack),
         channel_config <- Keyword.put(channel_config, :consumer_tag, consumer_tag) do
      Logger.debug fn -> "#{consumer_tag}: consumer bound to queue '#{queue}'" end
      {:ok, channel_config}
    else
      error ->
        error
    end
  end

  defp setup_channel(channel_config, :producer, channel, pattern, _queue) do
    with publisher_confirm <- pattern.publisher_confirm(channel_config),
         :ok <- setup_publisher_confirm(channel, publisher_confirm) do
      {:ok, channel_config}
    else
      error ->
        error
    end
  end

  defp setup_channel(channel_config, :passive, _channel, _pattern, _queue) do
    {:ok, channel_config}
  end

  defp setup_consumer_prefetch(_channel, nil = _consumer_prefetch), do: :ok
  defp setup_consumer_prefetch(channel, consumer_prefetch) do
    Basic.qos(channel, prefetch_count: consumer_prefetch)
  end

  defp setup_publisher_confirm(_channel, false = _publisher_confirm), do: :ok
  defp setup_publisher_confirm(channel, true = _publisher_confirm) do
    with :ok <- Confirm.select(channel),
         :ok <- Basic.return(channel, self()) do
      :ok
    else
      error ->
        error
    end
  end

  defp get_channel_config(channels, consumer_tag) do
    Enum.find(channels, fn channel_config ->
      consumer_tag == Keyword.get(channel_config, :consumer_tag)
    end)
  end

  defp get_channel_config(channels, exchange, routing_key) do
    Enum.find(channels, fn channel_config ->
      exchange == Keyword.get(channel_config, :exchange) && routing_key == Keyword.get(channel_config, :routing_key)
    end)
  end

  defp cleanup_configuration(configuration) do
    with :ok <- check_mandatory_params(configuration, @connection_mandatory_params),
         {_, configuration} <- Keyword.get_and_update(configuration, :host, fn host ->
           {host, map_host(host)}
         end),
         {_, configuration} <- Keyword.get_and_update(configuration, :port, fn port ->
           {port, map_port(port)}
         end),
         {_, configuration} = Keyword.get_and_update(configuration, :auth_mechanisms, fn
           mechanisms when is_list(mechanisms) ->
             {mechanisms, Enum.map(mechanisms, &map_auth_mechanism(&1))}
           _ ->
            :pop
        end) do
      {:ok, configuration}
    else
      {:error, :missing_params, missing_params} ->
        params = Enum.join(missing_params, ", ")
        error = "Error creating connection #{inspect configuration}: missing mandatory params: #{params}"
        Logger.error error
        {:error, error}
    end
  end

  defp check_mandatory_params(configuration, params) do
    if Enum.all?(params, &Keyword.has_key?(configuration, &1)) do
      :ok
    else
      missing_params = params
      |> Enum.reject(&Keyword.has_key?(configuration, &1))
      {:error, :missing_params, missing_params}
    end
  end

  defp map_auth_mechanism(:amqplain), do: &:amqp_auth_mechanisms.amqplain/3
  defp map_auth_mechanism(:external), do: &:amqp_auth_mechanisms.external/3
  defp map_auth_mechanism(:plain), do: &:amqp_auth_mechanisms.plain/3
  defp map_auth_mechanism(auth_mechanism), do: auth_mechanism

  defp map_host(nil), do: @default_rabbitmq_host
  defp map_host(host) when is_binary(host), do: String.to_charlist(host)
  defp map_host(host), do: host

  defp map_port(nil), do: @default_rabbitmq_port
  defp map_port(port) when is_binary(port), do: String.to_integer(port)
  defp map_port(port), do: port
end
