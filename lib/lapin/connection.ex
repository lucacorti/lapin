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

  alias AMQP.Channel
  alias Lapin.{Consumer, Exchange, Message, Producer, Queue}
  alias Lapin.Message.Payload

  @typedoc """
  Connection configuration

  The following keys are supported:
    - module: module using the `Lapin.Connection` behaviour
    - uri: AMQP URI (String.t | URI.t)
    - host: broker hostname (string | charlist), *default: 'localhost'*
    - port: broker port (string | integer), *default: 5672*
    - virtual_host: broker vhost (string), *default: "/"*
    - username: username (string)
    - password: password (string)
    - auth_mechanisms: broker auth_mechanisms ([:amqplain | :external | :plain]), *default: amqp_client default*
    - ssl_options: ssl options ([:ssl:ssl_option]), *default: none*
    - producers: producers to configure ([Producer.config]), *default: []*
    - consumers: consumers to configure ([Consumer.config]), *default: []*
  """
  @type config :: [consumers: [Consumer.config()], producers: [Producer.config()]]

  @typedoc "Connection"
  @type t :: GenServer.server()

  @typedoc "Callback result"
  @type on_callback :: :ok | {:error, message :: String.t()}

  @typedoc "Reason for message rejection"
  @type reason :: term

  @typedoc "`handle_deliver/2` callback result"
  @type on_deliver :: :ok | {:reject, reason} | term

  @doc """
  Called when receiving a `basic.cancel` from the broker.
  """
  @callback handle_cancel(Channel.t()) :: on_callback

  @doc """
  Called when receiving a `basic.cancel_ok` from the broker.
  """
  @callback handle_cancel_ok(Channel.t()) :: on_callback

  @doc """
  Called when receiving a `basic.consume_ok` from the broker.

  This signals successul registration as a consumer.
  """
  @callback handle_consume_ok(Channel.t()) :: on_callback

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
  @callback handle_deliver(Channel.t(), Message.t()) :: on_deliver

  @doc """
  Called when completing a `basic.publish` with the broker.

  Message transmission to the broker is successful when this callback is called.
  """
  @callback handle_publish(Channel.t(), Message.t()) :: on_callback

  @doc """
  Called when receiving a `basic.return` from the broker.

  This signals an undeliverable returned message from the broker.
  """
  @callback handle_return(Channel.t(), Message.t()) :: on_callback

  @doc """
  Called before `handle_deliver/2` to get the payload type.

  Should return a data type instance to decode the payload into.
  A `Lapin.Message.Payload` implementation must be provided for this type. The
  default implementation leaves the payload unaltered.
  """
  @callback payload_for(Channel.t(), Message.t()) :: Payload.t()

  defmacro __using__(_) do
    quote do
      alias Lapin.{Consumer, Message}

      @behaviour Lapin.Connection

      def handle_cancel(_consumer), do: :ok
      def handle_cancel_ok(_consumer), do: :ok
      def handle_consume_ok(_consumer), do: :ok
      def handle_deliver(_consumer, _message), do: :ok
      def handle_publish(_consumer, _message), do: :ok
      def handle_return(_consumer, _message), do: :ok
      def payload_for(_consumer, _message), do: <<>>

      defoverridable Lapin.Connection

      def publish(exchange, routing_key, message, options \\ []) do
        Lapin.Connection.publish(__MODULE__, exchange, routing_key, message, options)
      end
    end
  end

  @backoff 1_000
  @connection_default_params [connection_timeout: @backoff]
  @default_rabbitmq_host 'localhost'
  @default_rabbitmq_port 5672

  @doc """
  Starts a `Lapin.Connection` with the specified configuration
  """
  @spec start_link(config, options :: GenServer.options()) :: GenServer.on_start()
  def start_link(configuration, options \\ []) do
    {:ok, configuration} = cleanup_configuration(configuration)
    Connection.start_link(__MODULE__, configuration, options)
  end

  def init(configuration) do
    Process.flag(:trap_exit, true)
    {:connect, :init,
     %{configuration: configuration, consumers: [], producers: [], connection: nil, module: nil}}
  end

  @doc """
  Closes the connection
  """
  @spec close(connection :: t) :: on_callback()
  def close(connection), do: GenServer.stop(connection)

  def terminate(_reason, %{connection: nil}), do: :ok

  def terminate(_reason, %{connection: connection}) do
    AMQP.Connection.close(connection)
  end

  @doc """
  Publishes a message to the specified exchange with the given routing_key
  """
  @spec publish(
          connection :: t(),
          String.t(),
          String.t(),
          Payload.t(),
          options :: Keyword.t()
        ) :: on_callback
  def publish(connection, exchange, routing_key, payload, options \\ []) do
    Connection.call(connection, {:publish, exchange, routing_key, payload, options})
  end

  def handle_call(
        {:publish, _exchange, _routing_key, _payload, _options},
        _from,
        %{connection: nil} = state
      ) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(
        {:publish, exchange, routing_key, payload, options},
        _from,
        %{producers: producers, module: module} = state
      ) do
    with {:ok, %Producer{pattern: pattern} = producer} <- Producer.get(producers, exchange),
         mandatory <- pattern.mandatory(producer),
         persistent <- pattern.persistent(producer),
         options <- Keyword.merge([mandatory: mandatory, persistent: persistent], options),
         meta <- %{content_type: Payload.content_type(payload)},
         {:ok, payload} <- Payload.encode(payload),
         :ok <- Producer.publish(producer, exchange, routing_key, payload, options) do
      message = %Message{meta: Enum.into(options, meta), payload: payload}

      if not pattern.confirm(producer) or Producer.confirm(producer) do
        Logger.debug(fn -> "Published #{inspect(message)} on #{inspect(producer)}" end)
        {:reply, module.handle_publish(producer, message), state}
      else
        error = "Error publishing #{inspect(message)}"
        Logger.debug(fn -> error end)
        {:reply, {:error, error}, state}
      end
    else
      {:error, error} ->
        Logger.debug(fn -> "Error sending message: #{inspect(error)}" end)
        {:reply, {:error, error}, state}
    end
  end

  def handle_info(
        {:basic_cancel, %{consumer_tag: consumer_tag}},
        %{consumers: consumers, module: module} = state
      ) do
    with {:ok, consumer} <- Consumer.get(consumers, consumer_tag) do
      Logger.debug(fn -> "Broker cancelled consumer for #{inspect(consumer)}" end)
      module.handle_cancel(consumer)
    else
      nil ->
        Logger.warn(
          "Broker cancelled consumer_tag '#{consumer_tag}' for locally unknown consumer"
        )

      {:error, error} ->
        Logger.error("Error canceling consumer_tag '#{consumer_tag}': #{inspect(error)}")
    end

    {:stop, :normal, state}
  end

  def handle_info(
        {:basic_cancel_ok, %{consumer_tag: consumer_tag}},
        %{consumers: consumers, module: module} = state
      ) do
    with {:ok, consumer} <- Consumer.get(consumers, consumer_tag),
         :ok <- module.handle_cancel_ok(consumer) do
      Logger.debug(fn -> "Broker confirmed cancelling consumer for #{inspect(consumer)}" end)
    else
      {:error, :not_found} ->
        Logger.debug(fn ->
          "Broker confirmed cancelling consumer for locally unknown tag '#{consumer_tag}'"
        end)

      error ->
        Logger.error("Error handling broker cancel for '#{consumer_tag}': #{inspect(error)}")
    end

    {:noreply, state}
  end

  def handle_info(
        {:basic_consume_ok, %{consumer_tag: consumer_tag}},
        %{consumers: consumers, module: module} = state
      ) do
    with {:ok, consumer} <- Consumer.get(consumers, consumer_tag),
         :ok <- module.handle_consume_ok(consumer) do
      Logger.debug(fn -> "Broker registered consumer for #{inspect(consumer)}" end)
    else
      {:error, :not_found} ->
        Logger.warn(
          "Broker registered consumer_tag '#{consumer_tag}' for locally unknown consumer"
        )

      error ->
        Logger.error("Error handling broker register for '#{consumer_tag}': #{inspect(error)}")
    end

    {:noreply, state}
  end

  def handle_info(
        {:basic_return, payload, %{exchange: exchange} = meta},
        %{producers: producers, module: module} = state
      ) do
    message = %Message{meta: meta, payload: payload}

    with {:ok, producer} <- Producer.get(producers, exchange),
         :ok <- module.handle_return(producer, message) do
      Logger.debug(fn -> "Broker returned message #{inspect(message)}" end)
    else
      {:error, :not_found} ->
        Logger.warn("Broker returned message #{inspect(message)} for locally unknown channel")

      error ->
        Logger.debug(fn -> "Error handling returned message: #{inspect(error)}" end)
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, _pid, _reason}, state) do
    Logger.warn("Connection down, restarting...")
    {:stop, :normal, state}
  end

  def handle_info(
        {:basic_deliver, payload, %{consumer_tag: consumer_tag} = meta},
        %{consumers: consumers, module: module} = state
      ) do
    message = %Message{meta: meta, payload: payload}

    with {:ok, consumer} <- Consumer.get(consumers, consumer_tag) do
      spawn(fn -> consume(module, consumer, message) end)
    else
      {:error, :not_found} ->
        Logger.error("Error processing message #{inspect(message)}, no local consumer")
    end

    {:noreply, state}
  end

  defp consume(
         module,
         %Consumer{pattern: pattern} = consumer,
         %Message{
           meta: %{delivery_tag: delivery_tag, redelivered: redelivered} = meta,
           payload: payload
         } = message
       ) do
    with ack <- pattern.ack(consumer),
         payload_for <- module.payload_for(consumer, message),
         content_type <- Payload.content_type(payload_for),
         meta <- Map.put(meta, :content_type, content_type),
         {:ok, payload} <- Payload.decode_into(payload_for, payload),
         message <- %Message{message | meta: meta, payload: payload},
         :ok <- module.handle_deliver(consumer, message) do
      Logger.debug(fn -> "Consuming message #{delivery_tag}" end)
      consume_ack(ack, consumer, delivery_tag)
    else
      {:reject, reason} ->
        with :ok <- Consumer.reject_message(consumer, delivery_tag, false) do
          Logger.error("Rejected message #{delivery_tag}: #{inspect(reason)}")
        else
          {:error, reason} ->
            Logger.debug("Failed rejecting message #{delivery_tag}: #{inspect(reason)}")
        end

      reason ->
        with :ok <- Consumer.reject_message(consumer, delivery_tag, not redelivered) do
          Logger.error("Rejected message #{delivery_tag}: #{inspect(reason)}")
        else
          {:error, reason} ->
            Logger.debug("Failed rejecting message #{delivery_tag}: #{inspect(reason)}")
        end
    end
  rescue
    exception ->
      with :ok <- Consumer.reject_message(consumer, delivery_tag, not redelivered) do
        Logger.error("Rejected message #{delivery_tag}: #{inspect(exception)}")
      else
        error ->
          Logger.debug("Failed rejecting message #{delivery_tag}: #{inspect(error)}")
      end
  end

  defp consume_ack(true = _ack, consumer, delivery_tag) do
    with :ok <- Consumer.ack_message(consumer, delivery_tag) do
      Logger.debug("Consumed message #{delivery_tag} successfully, ACK sent")
      :ok
    else
      error ->
        Logger.debug("ACK failed for message #{delivery_tag}")
        error
    end
  end

  defp consume_ack(false = _ack, _channel, delivery_tag) do
    Logger.debug(fn -> "Consumed message #{delivery_tag}, ACK not required" end)
    :ok
  end

  def connect(_info, %{configuration: configuration} = state) do
    module = Keyword.get(configuration, :module)

    with configuration <- Keyword.merge(@connection_default_params, configuration),
         {:ok, connection} <- AMQP.Connection.open(configuration),
         {:ok, config_channel} <- Channel.open(connection),
         exchanges <- Keyword.get(configuration, :exchanges, []),
         exchanges <- Enum.map(exchanges, &Exchange.new/1),
         :ok <-
           Enum.reduce_while(exchanges, :ok, fn exchange, acc ->
             case Exchange.declare(exchange, config_channel) do
               :ok ->
                 {:cont, acc}

               error ->
                 {:halt, error}
             end
           end),
         queues <- Keyword.get(configuration, :queues, []),
         queues <- Enum.map(queues, &Queue.new/1),
         :ok <-
           Enum.reduce_while(queues, :ok, fn queue, acc ->
             case Queue.declare(queue, config_channel) do
               :ok ->
                 {:cont, acc}

               error ->
                 {:halt, error}
             end
           end),
         :ok <-
           Enum.reduce_while(exchanges, :ok, fn exchange, acc ->
             case Exchange.bind(exchange, config_channel) do
               :ok ->
                 {:cont, acc}

               error ->
                 {:halt, error}
             end
           end),
         :ok <-
           Enum.reduce_while(queues, :ok, fn queue, acc ->
             case Queue.bind(queue, config_channel) do
               :ok ->
                 {:cont, acc}

               error ->
                 {:halt, error}
             end
           end),
         producers <- Keyword.get(configuration, :producers, []),
         producers <- Enum.map(producers, &Producer.create(connection, &1)),
         consumers <- Keyword.get(configuration, :consumers, []),
         consumers <- Enum.map(consumers, &Consumer.create(connection, &1)),
         :ok <- Channel.close(config_channel) do
      Process.monitor(connection.pid)

      {:ok,
       %{
         state
         | module: module,
           producers: producers,
           consumers: consumers,
           connection: connection
       }}
    else
      {:error, error} ->
        Logger.error(fn ->
          "Connection error: #{inspect(error)} for #{module}, backing off for #{@backoff}"
        end)

        {:backoff, @backoff, state}
    end
  end

  defp cleanup_configuration(configuration) do
    with :ok <- check_mandatory_params(configuration, [:module]),
         {uri, configuration} <-
           Keyword.get_and_update(configuration, :uri, fn uri ->
             {map_uri(uri), :pop}
           end),
         configuration <- Keyword.merge(configuration, uri),
         {_, configuration} <-
           Keyword.get_and_update(configuration, :host, fn host ->
             {host, map_host(host)}
           end),
         {_, configuration} <-
           Keyword.get_and_update(configuration, :port, fn port ->
             {port, map_port(port)}
           end),
         {_, configuration} <-
           Keyword.get_and_update(configuration, :virtual_host, fn vhost ->
             {vhost, map_vhost(vhost)}
           end),
         {_, configuration} =
           Keyword.get_and_update(configuration, :auth_mechanisms, fn
             mechanisms when is_list(mechanisms) ->
               {mechanisms, Enum.map(mechanisms, &map_auth_mechanism(&1))}

             _ ->
               :pop
           end) do
      {:ok, configuration}
    else
      {:error, :missing_params, missing_params} ->
        params = Enum.join(missing_params, ", ")

        error =
          "Error creating connection #{inspect(configuration)}: missing mandatory params: #{
            params
          }"

        Logger.error(error)
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
    with {path, uri} <- Keyword.pop(uri, :path),
         {userinfo, uri} <- Keyword.pop(uri, :userinfo),
         uri <- Keyword.drop(uri, [:authority, :query, :fragment, :scheme]),
         [username, password] <- map_userinfo(userinfo) do
      uri
      |> Keyword.put(:virtual_host, map_vhost(path))
      |> Keyword.put(:username, username)
      |> Keyword.put(:password, password)
      |> Enum.reject(fn {_k, v} -> v === nil end)
    end
  end

  defp map_userinfo(userinfo) when is_binary(userinfo) do
    parts =
      userinfo
      |> String.split(":", parts: 2)

    [Enum.at(parts, 0), Enum.at(parts, 1)]
  end

  defp map_userinfo(_), do: [nil, nil]

  defp map_vhost(nil), do: "/"

  defp map_vhost(path) do
    case String.replace_leading(path, "/", "") do
      "" -> "/"
      vhost -> vhost
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

  defp check_mandatory_params(configuration, params) do
    if Enum.all?(params, &Keyword.has_key?(configuration, &1)) do
      :ok
    else
      missing_params = Enum.reject(params, &Keyword.has_key?(configuration, &1))
      {:error, :missing_params, missing_params}
    end
  end
end
