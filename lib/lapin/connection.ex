defmodule Lapin.Connection do
  @moduledoc """
  RabbitMQ connection handler

  This module handles the RabbitMQ connection. It also provides a behaviour for
  worker module implementation. The worker module should use the `Lapin.Connection`
  behaviour and implement the callbacks it needs.

  When using the `Lapin.Connection` behaviour a `publish/4` function is injected in
  the worker module as a shortcut to the `Lapin.Connection.publish/5` function
  which removes the need for passing in the connection and is publicly callable
  to publish messages on the connection configured for the implementing module.
  """

  use GenServer

  use AMQP

  require Logger

  import Lapin.Utils, only: [check_mandatory_params: 2]

  alias Lapin.{Message, Channel}

  @typedoc """
  Connection configuration

  The following keys are supported:
    - module: module using the `Lapin.Connection` behaviour
    - host: broker hostname (string | charlist), *default: 'localhost'*
    - port: broker port (string | integer), *default: 5672*
    - virtual_host: broker vhost (string), *default: ""*
    - username: username (string)
    - password: password (string)
    - auth_mechanisms: broker auth_mechanisms ([:amqplain | :external | :plain]), *default: amqp_client default*
    - ssl_options: ssl options ([:ssl:ssl_option]), *default: none*
    - channels: channels to configure ([Channel.config]), *default: []*
  """
  @type config :: [channels: [Channel.config]]

  @typedoc "Connection"
  @type t :: GenServer.server

  @typedoc "Callback result"
  @type on_callback :: :ok | {:error, message :: String.t}

  @typedoc "Reason for message rejection"
  @type reason :: term

  @typedoc "`handle_deliver/2` callback result"
  @type on_deliver :: :ok | {:requeue, reason} | term

  @doc """
  Called when receiving a `basic.cancel` from the broker.
  """
  @callback handle_cancel(Channel.t) :: on_callback

  @doc """
  Called when receiving a `basic.cancel_ok` from the broker.
  """
  @callback handle_cancel_ok(Channel.t) :: on_callback

  @doc """
  Called when receiving a `basic.deliver` from the broker.

  Return values from this callback determine message acknowledgement:
    - `:ok`: Message was processed by the consumer and should be removed from queue
    - `{:requeue, reason}`: Message was not processed and should be requeued

  Any other return value, including a crash in the callback code, rejects the
  message WITHOUT requeueing. The `reason` term can be used by the application
  to signal the reason of rejection and is logged in debug.
  """
  @callback handle_deliver(Channel.t, Message.t) :: on_deliver

  @doc """
  Called when receiving a `basic.consume_ok` from the broker.

  This signals successul registration as a consumer.
  """
  @callback handle_consume_ok(Channel.t) :: on_callback

  @doc """
  Called when completing a `basic.publish` with the broker.

  Message transmission to the broker is successful when this callback is called.
  """
  @callback handle_publish(Channel.t, Message.t) :: on_callback

  @doc """
  Called when receiving a `basic.return` from the broker.

  This signals an undeliverable returned message from the broker.
  """
  @callback handle_return(Channel.t, Message.t) :: on_callback

  defmacro __using__(_) do
    quote do
      alias Lapin.{Channel, Message}

      @behaviour Lapin.Connection

      def handle_cancel(_channel), do: :ok
      def handle_cancel_ok(_channel), do: :ok
      def handle_consume_ok(_channel), do: :ok
      def handle_deliver(_channel, _message), do: :ok
      def handle_publish(_channel,_message), do: :ok
      def handle_return(_channel, _message), do: :ok

      defoverridable Lapin.Connection

      def publish(exchange, routing_key, message, options \\ []) do
        Conn.publish(__MODULE__, exchange, routing_key, message, options)
      end
    end
  end

  @default_reconnection_delay 5_000
  @connection_default_params [connecion_timeout: @default_reconnection_delay]
  @default_rabbitmq_host 'localhost'
  @default_rabbitmq_port 5672

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
  @spec publish(connection :: t, Channel.exchange, Channel.routing_key, Message.t, options :: Keyword.t) :: on_callback
  def publish(connection, exchange, routing_key, message, options \\ []) do
    GenServer.call(connection, {:publish, exchange, routing_key, message, options})
  end

  def handle_call({:publish, exchange, routing_key, %Message{meta: meta} = message, options}, _from,
  %{channels: channels, configuration: configuration} = state) do
    with module <- Keyword.get(configuration, :module),
         channel when not is_nil(channel) <- Channel.get(channels, exchange, routing_key),
         :producer <- channel.role,
         amqp_channel when not is_nil(amqp_channel) <- channel.amqp_channel,
         mandatory <- channel.pattern.publisher_mandatory(channel),
         persistent <- channel.pattern.publisher_persistent(channel),
         options <- Keyword.merge([mandatory: mandatory, persistent: persistent], options),
         :ok <- Basic.publish(amqp_channel, exchange, routing_key, message.payload, options) do
      if not channel.pattern.publisher_confirm(channel) or Confirm.wait_for_confirms(channel) do
        message = %Message{message | meta: Enum.into(options, meta)}
        Logger.debug fn -> "Published #{inspect message} on #{inspect channel}" end
        {:reply, module.handle_publish(channel, message), state}
      else
        error = "Error publishing #{inspect message}"
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
         channel when not is_nil(channel) <- Channel.get(channels, consumer_tag) do
      Logger.debug fn -> "Broker cancelled consumer for #{inspect channel}" end
      module.handle_cancel(channel)
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
         channel when not is_nil(channel) <- Channel.get(channels, consumer_tag),
         :ok <- module.handle_cancel_ok(channel) do
      Logger.debug fn -> "Broker confirmed cancelling consumer for #{inspect channel}" end
    else
      nil ->
        Logger.debug fn -> "Broker confirmed cancelling consumer for locally unknown tag '#{consumer_tag}'" end
      error ->
        Logger.error "Error handling broker cancel for '#{consumer_tag}': #{inspect error}"
    end
    {:noreply, state}
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}},
  %{channels: channels, configuration: configuration} = state) do
    with module <- Keyword.get(configuration, :module),
         channel when not is_nil(channel) <- Channel.get(channels, consumer_tag),
         :ok <- module.handle_consume_ok(channel) do
      Logger.debug fn -> "Broker registered consumer for #{inspect channel}" end
    else
      nil ->
        Logger.warn "Broker registered consumer_tag '#{consumer_tag}' for locally unknown channel"
      error ->
        Logger.error "Error handling broker register for '#{consumer_tag}': #{inspect error}"
    end
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, %{consumer_tag: consumer_tag} = meta},
  %{channels: channels, configuration: configuration} = state) do
    message = %Message{meta: meta, payload: payload}
    with module <- Keyword.get(configuration, :module),
         channel when not is_nil(channel) <- Channel.get(channels, consumer_tag) do
      spawn(fn ->
        consume(module, channel, message)
      end)
    else
      nil ->
        Logger.error "Error processing message '#{inspect message}', no local channel"
    end
    {:noreply, state}
  end

  def handle_info({:basic_return, payload, %{exchange: exchange, routing_key: routing_key} = meta},
  %{channels: channels, configuration: configuration} = state) do
    module = Keyword.get(configuration, :module)
    message = %Message{meta: meta, payload: payload}
    with channel when not is_nil(channel) <- Channel.get(channels, exchange, routing_key),
         :ok <- module.handle_return(channel, message) do
      Logger.debug fn -> "Broker returned message '#{inspect message}'" end
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

  def terminate(_reason, %{connection: connection}) do
    Connection.close(connection)
  end

  defp consume(module, channel, %Message{meta: %{delivery_tag: delivery_tag}} = message) do
    Logger.debug fn -> "Consuming message '#{delivery_tag}'" end

    with pattern = Keyword.get(channel, :pattern),
         consumer_ack <- pattern.consumer_ack(channel),
         :ok <- module.handle_deliver(channel, message) do
      consume_ack(consumer_ack, channel.amqp_channel, delivery_tag)
     else
      {:requeue, reason} ->
        Basic.reject(channel.amqp_channel, delivery_tag, requeue: true)
        Logger.debug fn -> "Requeued message '#{delivery_tag}': #{inspect reason}" end
      reason ->
        Basic.reject(channel.amqp_channel, delivery_tag, requeue: false)
        Logger.debug fn -> "Rejected message #{delivery_tag}: #{inspect reason}" end
    end

    rescue
      exception ->
        Basic.reject(channel.amqp_channel, delivery_tag, requeue: false)
        Logger.error "Rejected message #{delivery_tag}: #{inspect exception}"
  end

  defp consume_ack(true = _consumer_ack, channel, delivery_tag) do
    if Basic.ack(channel.amqp_channel, delivery_tag) do
      Logger.debug fn -> "Consumed message #{delivery_tag} successfully, ACK" end
      :ok
    else
      Logger.debug fn -> "ACK failed for message #{delivery_tag}" end
      :error
    end
  end

  defp consume_ack(false = _consumer_ack, _channel, delivery_tag) do
    Logger.debug fn -> "Consumed message #{delivery_tag}, no ACK required" end
    :ok
  end

  defp connect(configuration) do
    with {channels, configuration} <- Keyword.pop(configuration, :channels, []),
         configuration <- Keyword.merge(@connection_default_params, configuration),
         {:ok, connection} <- Connection.open(configuration) do
      Process.monitor(connection.pid)
      {:ok, connection, Enum.map(channels, &Channel.create(connection, &1))}
    else
      {:error, _} ->
        :timer.sleep(@default_reconnection_delay)
        connect(configuration)
    end
  end

  defp cleanup_configuration(configuration) do
    with :ok <- check_mandatory_params(configuration, [:module]),
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
