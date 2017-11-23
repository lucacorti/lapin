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

  use Connection

  require Logger

  import Lapin.Utils, only: [check_mandatory_params: 2]

  alias Lapin.{Message, Channel}

  @typedoc """
  Connection configuration

  The following keys are supported:
    - module: module using the `Lapin.Connection` behaviour
    - uri: AMQP uri, takes precedence over individual parameters below (String.t | URI.t)
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
  @type on_deliver :: :ok | {:reject, reason} | term

  @doc """
  Called when receiving a `basic.cancel` from the broker.
  """
  @callback handle_cancel(Channel.t) :: on_callback

  @doc """
  Called when receiving a `basic.cancel_ok` from the broker.
  """
  @callback handle_cancel_ok(Channel.t) :: on_callback

  @doc """
  Called when receiving a `basic.consume_ok` from the broker.

  This signals successul registration as a consumer.
  """
  @callback handle_consume_ok(Channel.t) :: on_callback

  @doc """
  Called when receiving a `basic.deliver` from the broker.

  Return values from this callback determine message acknowledgement:
    - `:ok`: Message was processed by the consumer and should be removed from queue
    - `{:reject, reason}`: Message was not processed and should be rejected

  Any other return value requeues the message to prevent data loss.
  A crash in the callback code will however reject the message to prevent loops
  if the message was already delivered before.

  The `reason` term can be used by the application
  to signal the reason of rejection and is logged in debug.
  """
  @callback handle_deliver(Channel.t, Message.t) :: on_deliver

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

  @doc """
  Called before `handle_deliver/2` to get the payload type.

  Should return a data type instance to decode the payload into.
  A `Lapin.Message.Payload` implementation must be provided for this type. The
  default implementation leaves the payload unaltered.
  """
  @callback payload_for(Channel.t, Message.t) :: Message.Payload.t

  defmacro __using__(_) do
    quote do
      alias Lapin.{Channel, Message}

      @behaviour Lapin.Connection

      def handle_cancel(_channel), do: :ok
      def handle_cancel_ok(_channel), do: :ok
      def handle_consume_ok(_channel), do: :ok
      def handle_deliver(_channel, _message), do: :ok
      def handle_publish(_channel, _message), do: :ok
      def handle_return(_channel, _message), do: :ok
      def payload_for(_channel, _message), do: <<>>

      defoverridable Lapin.Connection

      def publish(exchange, routing_key, message, options \\ []) do
        Lapin.Connection.publish(__MODULE__, exchange, routing_key, message, options)
      end
    end
  end

  @backoff 1_000
  @connection_default_params [connecion_timeout: @backoff]
  @default_rabbitmq_host 'localhost'
  @default_rabbitmq_port 5672

  @doc """
  Starts a `Lapin.Connection` with the specified configuration
  """
  @spec start_link(config, options :: GenServer.options) :: GenServer.on_start
  def start_link(configuration, options \\ []) do
    {:ok, configuration} = cleanup_configuration(configuration)
    Connection.start_link(__MODULE__, configuration, options)
  end

  def init(configuration) do
    {:connect, :init,  %{configuration: configuration, channels: [], connection: nil, module: nil}}
  end

  @doc """
  Closes the connection
  """
  @spec close(connection :: t) :: GenServer.on_callback
  def close(connection), do: GenServer.stop(connection)

  def terminate(_reason, %{connection: nil}), do: :ok
  def terminate(_reason, %{connection: connection}) do
    AMQP.Connection.close(connection)
  end

  @doc """
  Publishes a message to the specified exchange with the given routing_key
  """
  @spec publish(connection :: t, Channel.exchange, Channel.routing_key, Message.Payload.t, options :: Keyword.t) :: on_callback
  def publish(connection, exchange, routing_key, payload, options \\ []) do
    Connection.call(connection, {:publish, exchange, routing_key, payload, options})
  end

  def handle_call({:publish, _exchange, _routing_key, _payload, _options}, _from, %{connection: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:publish, exchange, routing_key, payload, options}, _from, %{channels: channels, module: module} = state) do
    with channel when not is_nil(channel) <- Channel.get(channels, exchange, routing_key, :producer),
         %Channel{pattern: pattern} <- channel,
         amqp_channel when not is_nil(amqp_channel) <- channel.amqp_channel,
         mandatory <- pattern.publisher_mandatory(channel),
         persistent <- pattern.publisher_persistent(channel),
         options <- Keyword.merge([mandatory: mandatory, persistent: persistent], options),
         content_type <- Message.Payload.content_type(payload),
         meta <- %{content_type: content_type},
         {:ok, payload} <- Message.Payload.encode(payload),
         :ok <- AMQP.Basic.publish(amqp_channel, exchange, routing_key, payload, options) do
      message = %Message{meta: Enum.into(options, meta), payload: payload}
      if not pattern.publisher_confirm(channel) or AMQP.Confirm.wait_for_confirms(amqp_channel) do
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
        error = "Error publishing message: no channel for exchange '#{exchange}' with routing key '#{routing_key}'"
        Logger.debug fn -> error end
        {:reply, {:error, error}, state}
      {:error, error} ->
        Logger.debug fn -> "Error sending message: #{inspect error}" end
        {:reply, {:error, error}, state}
    end
  end

  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, %{channels: channels, module: module} = state) do
    with channel when not is_nil(channel) <- Channel.get(channels, consumer_tag) do
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

  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, %{channels: channels, module: module} = state) do
    with channel when not is_nil(channel) <- Channel.get(channels, consumer_tag),
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

  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, %{channels: channels, module: module} = state) do
    with channel when not is_nil(channel) <- Channel.get(channels, consumer_tag),
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

  def handle_info({:basic_return, payload, %{exchange: exchange, routing_key: routing_key} = meta}, %{channels: channels, module: module} = state) do
    message = %Message{meta: meta, payload: payload}
    with channel when not is_nil(channel) <- Channel.get(channels, exchange, routing_key, :producer),
         :ok <- module.handle_return(channel, message) do
      Logger.debug fn -> "Broker returned message #{inspect message}" end
    else
      nil ->
        Logger.warn "Broker returned message #{inspect message} for locally unknown channel"
      error ->
        Logger.debug fn -> "Error handling returned message: #{inspect error}" end
    end
    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, _pid, _reason}, state) do
    Logger.warn "Connection down, restarting..."
    {:stop, :normal, state}
  end

  def handle_info({:basic_deliver, payload, %{consumer_tag: consumer_tag} = meta}, %{channels: channels, module: module} = state) do
    message = %Message{meta: meta, payload: payload}
    with channel when not is_nil(channel) <- Channel.get(channels, consumer_tag) do
      spawn(fn -> consume(module, channel, meta, payload) end)
    else
      nil ->
        Logger.error "Error processing message #{inspect message}, no local channel"
    end
    {:noreply, state}
  end

  defp consume(module, %Channel{pattern: pattern} = channel, %{delivery_tag: delivery_tag, redelivered: redelivered} = meta, payload) do
    message = %Message{meta: meta, payload: payload}
    with consumer_ack <- pattern.consumer_ack(channel),
         payload_for <- module.payload_for(channel, message),
         content_type <- Message.Payload.content_type(payload_for),
         message <- %Message{message | meta: Map.put(meta, :content_type, content_type)},
         {:ok, payload} <- Message.Payload.decode_into(payload_for, payload),
         message <- %Message{message | payload: payload},
         :ok <- module.handle_deliver(channel, message) do
      Logger.debug fn -> "Consuming message #{delivery_tag}" end
      consume_ack(consumer_ack, channel.amqp_channel, delivery_tag)
    else
      {:reject, reason} ->
        AMQP.Basic.reject(channel.amqp_channel, delivery_tag, requeue: false)
        Logger.debug fn -> "Rejected message #{delivery_tag}: #{inspect reason}" end
      reason ->
        AMQP.Basic.reject(channel.amqp_channel, delivery_tag, requeue: not redelivered)
        Logger.debug fn -> "Requeued message #{delivery_tag}: #{inspect reason}" end
    end

    rescue
      exception ->
        AMQP.Basic.reject(channel.amqp_channel, delivery_tag, requeue: not redelivered)
        Logger.error "Rejected message #{delivery_tag}: #{inspect exception}"
  end

  defp consume_ack(true = _consumer_ack, amqp_channel, delivery_tag) do
    if AMQP.Basic.ack(amqp_channel, delivery_tag) do
      Logger.debug fn -> "Consumed message #{delivery_tag} successfully, ACK sent" end
      :ok
    else
      Logger.debug fn -> "ACK failed for message #{delivery_tag}" end
      :error
    end
  end

  defp consume_ack(false = _consumer_ack, _amqp_channel, delivery_tag) do
    Logger.debug fn -> "Consumed message #{delivery_tag}, ACK not required" end
    :ok
  end

  def connect(_info, %{configuration: configuration} = state) do
    with module <- Keyword.get(configuration, :module),
         channels <- Keyword.get(configuration, :channels, []),
         configuration <- Keyword.merge(@connection_default_params, configuration),
         {:ok, connection} <- AMQP.Connection.open(configuration),
         channels <- Enum.map(channels, &Channel.create(connection, &1)) do
      Process.monitor(connection.pid)
      {:ok, %{state | module: module, channels: channels, connection: connection}}
    else
      {:error, error} ->
        Logger.error fn -> "Connection error: #{error} for #{inspect configuration}, backing off for #{@backoff}" end
        {:backoff, @backoff, state}
    end
  end

  defp cleanup_configuration(configuration) do
    with :ok <- check_mandatory_params(configuration, [:module]),
         {uri, configuration} <- Keyword.get_and_update(configuration, :uri, fn uri ->
           {map_uri(uri), :pop}
         end),
         configuration <- Keyword.merge(configuration, uri),
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

  defp map_uri(nil), do: []

  defp map_uri(uri) when is_binary(uri) do
    uri
    |> URI.parse()
    |> map_uri()
  end

  defp map_uri(%URI{} = uri) do
    uri
    |> Map.from_struct()
    |> Enum.to_list()
    |> uri_to_list()
  end

  defp uri_to_list(uri) when is_list(uri) do
    with {vhost, uri} <- Keyword.pop(uri, :path),
         {userinfo, uri} <- Keyword.pop(uri, :userinfo),
         uri <- Keyword.drop(uri, [:authority, :query, :fragment, :scheme]),
         [username, password] <- map_userinfo(userinfo) do
      uri
      |> Keyword.put(:vhost, vhost)
      |> Keyword.put(:username, username)
      |> Keyword.put(:password, password)
      |> Enum.reject(fn {_k, v} -> v === nil end)
    end
  end

  defp map_userinfo(userinfo) when is_binary(userinfo) do
    parts = userinfo
    |> String.split(":", parts: 2)
    [Enum.at(parts, 0), Enum.at(parts, 1)]
  end

  defp map_userinfo(_), do: [nil, nil]

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
