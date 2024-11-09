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

  require Logger

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
  @type t :: :gen_statem.server_ref()

  @typedoc "Callback result"
  @type on_callback :: :ok | {:error, message :: String.t()}

  @typedoc "Reason for message rejection"
  @type reason :: term()

  @typedoc "`handle_deliver/2` callback result"
  @type on_deliver :: :ok | {:reject, reason} | term()

  @doc """
  Called when receiving a `basic.cancel` from the broker.
  """
  @callback handle_cancel(Consumer.t()) :: on_callback

  @doc """
  Called when receiving a `basic.cancel_ok` from the broker.
  """
  @callback handle_cancel_ok(Consumer.t()) :: on_callback

  @doc """
  Called when receiving a `basic.consume_ok` from the broker.

  This signals successul registration as a consumer.
  """
  @callback handle_consume_ok(Consumer.t()) :: on_callback

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
  @callback handle_deliver(Consumer.t(), Message.t()) :: on_deliver

  @doc """
  Called when completing a `basic.publish` with the broker.

  Message transmission to the broker is successful when this callback is called.
  """
  @callback handle_publish(Producer.t(), Message.t()) :: on_callback

  @doc """
  Called when receiving a `basic.return` from the broker.

  This signals an undeliverable returned message from the broker.
  """
  @callback handle_return(Consumer.t(), Message.t()) :: on_callback

  @doc """
  Called before `handle_deliver/2` to get the payload type.

  Should return a data type instance to decode the payload into.
  A `Lapin.Message.Payload` implementation must be provided for this type. The
  default implementation leaves the payload unaltered.
  """
  @callback payload_for(Consumer.t(), Message.t()) :: Payload.t()

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
  @default_rabbitmq_host ~c"localhost"
  @default_rabbitmq_port 5672

  @doc """
  Starts a `Lapin.Connection` with the specified configuration
  """
  @spec start_link(config, options :: GenServer.options()) :: GenServer.on_start()
  def start_link(configuration, options \\ []) do
    {:ok, configuration} = cleanup_configuration(configuration)
    :gen_statem.start_link({:local, options[:name]}, __MODULE__, configuration, [])
  end

  @doc """
  Closes the connection
  """
  @spec close(connection :: t) :: on_callback()
  def close(connection), do: :gen_statem.stop(connection)

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
  def publish(connection, exchange, routing_key, payload, options \\ []),
    do: :gen_statem.call(connection, {:publish, exchange, routing_key, payload, options})

  @behaviour :gen_statem

  @impl :gen_statem
  def callback_mode, do: [:handle_event_function, :state_enter]

  @impl :gen_statem
  def init(configuration) do
    {
      :ok,
      :disconnected,
      %{
        configuration: configuration,
        connection: nil,
        consumers: [],
        producers: [],
        module: nil
      },
      {:next_event, :internal, :connect}
    }
  end

  @impl :gen_statem
  def handle_event(:enter, old_state, current_state, _data) do
    Logger.info("#{inspect(old_state)} -> #{inspect(current_state)}")
    :keep_state_and_data
  end

  @impl :gen_statem
  def handle_event(
        {:call, from},
        {:publish, _exchange, _routing_key, _payload, _options},
        :disconnected,
        %{connection: nil}
      ) do
    {:keep_state_and_data, {:reply, from, {:error, :not_connected}}}
  end

  @impl :gen_statem
  def handle_event(
        {:call, from},
        {:publish, exchange, routing_key, payload, options},
        :connected,
        %{producers: producers, module: module}
      ) do
    with {:ok, %Producer{pattern: pattern} = producer} <- Producer.get(producers, exchange),
         mandatory = pattern.mandatory(producer),
         persistent = pattern.persistent(producer),
         options = Keyword.merge([mandatory: mandatory, persistent: persistent], options),
         meta = %{content_type: Payload.content_type(payload)},
         {:ok, payload} <- Payload.encode(payload),
         :ok <- Producer.publish(producer, exchange, routing_key, payload, options) do
      message = %Message{meta: Enum.into(options, meta), payload: payload}

      if not pattern.confirm(producer) or Producer.confirm(producer) do
        Logger.debug(fn -> "Published #{inspect(message)} on #{inspect(producer)}" end)
        {:keep_state_and_data, {:reply, from, module.handle_publish(producer, message)}}
      else
        error = "Error publishing #{inspect(message)}"
        Logger.debug(fn -> error end)
        {:keep_state_and_data, {:reply, from, {:error, error}}}
      end
    else
      {:error, error} ->
        Logger.debug(fn -> "Error sending message: #{inspect(error)}" end)
        {:keep_state_and_data, {:reply, from, {:error, error}}}
    end
  end

  @impl :gen_statem
  def handle_event(
        :info,
        {:basic_cancel, %{consumer_tag: consumer_tag}},
        :connected,
        %{consumers: consumers, module: module}
      ) do
    case Consumer.get(consumers, consumer_tag) do
      {:ok, consumer} ->
        Logger.debug(fn -> "Broker cancelled consumer for #{inspect(consumer)}" end)
        module.handle_cancel(consumer)

      {:error, :not_found} ->
        Logger.warning(
          "Broker cancelled consumer_tag '#{consumer_tag}' for locally unknown consumer"
        )
    end

    {:stop, :normal}
  end

  @impl :gen_statem
  def handle_event(
        :info,
        {:basic_cancel_ok, %{consumer_tag: consumer_tag}},
        :connected,
        %{consumers: consumers, module: module}
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

    :keep_state_and_data
  end

  @impl :gen_statem
  def handle_event(
        :info,
        {:basic_consume_ok, %{consumer_tag: consumer_tag}},
        :connected,
        %{consumers: consumers, module: module}
      ) do
    with {:ok, consumer} <- Consumer.get(consumers, consumer_tag),
         :ok <- module.handle_consume_ok(consumer) do
      Logger.debug(fn -> "Broker registered consumer for #{inspect(consumer)}" end)
    else
      {:error, :not_found} ->
        Logger.warning(
          "Broker registered consumer_tag '#{consumer_tag}' for locally unknown consumer"
        )

      error ->
        Logger.error("Error handling broker register for '#{consumer_tag}': #{inspect(error)}")
    end

    :keep_state_and_data
  end

  @impl :gen_statem
  def handle_event(
        :info,
        {:basic_return, payload, %{exchange: exchange} = meta},
        :connected,
        %{producers: producers, module: module}
      ) do
    message = %Message{meta: meta, payload: payload}

    with {:ok, producer} <- Producer.get(producers, exchange),
         :ok <- module.handle_return(producer, %Message{meta: meta, payload: payload}) do
      Logger.debug(fn -> "Broker returned message #{inspect(message)}" end)
    else
      {:error, :not_found} ->
        Logger.warning("Broker returned message #{inspect(message)} for locally unknown channel")

      error ->
        Logger.debug(fn -> "Error handling returned message: #{inspect(error)}" end)
    end

    :keep_state_and_data
  end

  @impl :gen_statem
  def handle_event(:info, {:DOWN, _, :process, _pid, _reason}, :connected, _data) do
    Logger.warning("Connection down, reconnecting...")
    {:stop, :normal}
  end

  @impl :gen_statem
  def handle_event(
        :info,
        {:basic_deliver, payload, %{consumer_tag: consumer_tag} = meta},
        :connected,
        %{consumers: consumers, module: module}
      ) do
    message = %Message{meta: meta, payload: payload}

    case Consumer.get(consumers, consumer_tag) do
      {:ok, consumer} ->
        spawn(fn -> consume(module, consumer, message) end)

      {:error, :not_found} ->
        Logger.error("Error processing message #{inspect(message)}, no local consumer")
    end

    :keep_state_and_data
  end

  @impl :gen_statem
  def handle_event(:internal, :disconnect, _state, data) do
    {
      :next_state,
      :disconnected,
      data,
      {:state_timeout, @backoff, nil}
    }
  end

  @impl :gen_statem
  def handle_event(:internal, :connect, :disconnected, %{configuration: configuration} = data) do
    module = Keyword.get(configuration, :module)

    with configuration <- Keyword.merge(@connection_default_params, configuration),
         {:ok, connection} <- AMQP.Connection.open(configuration),
         _ref = Process.monitor(connection.pid),
         {:ok, config_channel} <- AMQP.Channel.open(connection),
         {:ok, exchanges} <- declare_exchanges(configuration, config_channel),
         {:ok, queues} <- declare_queues(configuration, config_channel),
         :ok <- bind_exchanges(exchanges, config_channel),
         :ok <- bind_queues(queues, config_channel),
         {:ok, producers} <- create_producers(configuration, connection),
         {:ok, consumers} <- create_consumers(configuration, connection),
         :ok <- AMQP.Channel.close(config_channel) do
      {
        :next_state,
        :connected,
        %{
          data
          | module: module,
            producers: producers,
            consumers: consumers,
            connection: connection
        }
      }
    else
      {:error, error} ->
        Logger.error(fn ->
          "Connection error: #{inspect(error)} for #{module}, backing off for #{@backoff}"
        end)

        {:keep_state_and_data, {:state_timeout, @backoff, nil}}
    end
  end

  @impl :gen_statem
  def handle_event(:state_timeout, _event, :disconnected, _data),
    do: {:keep_state_and_data, {:next_event, :internal, :connect}}

  defp consume(
         module,
         %Consumer{pattern: pattern} = consumer,
         %Message{
           meta: %{delivery_tag: delivery_tag, redelivered: redelivered} = meta,
           payload: payload
         } = message
       ) do
    payload_for = module.payload_for(consumer, message)

    with {:ok, payload} <- Payload.decode_into(payload_for, payload),
         ack = pattern.ack(consumer),
         content_type = Payload.content_type(payload_for),
         meta = Map.put(meta, :content_type, content_type),
         :ok <- module.handle_deliver(consumer, %Message{message | meta: meta, payload: payload}) do
      Logger.debug(fn -> "Consuming message #{delivery_tag}" end)
      consume_ack(ack, consumer, delivery_tag)
    else
      {:reject, reason} ->
        case Consumer.reject_message(consumer, delivery_tag, false) do
          :ok ->
            Logger.error("Rejected message #{delivery_tag}: #{inspect(reason)}")
            :ok

          {:error, reason} ->
            Logger.debug("Failed rejecting message #{delivery_tag}: #{inspect(reason)}")
        end

      reason ->
        case Consumer.reject_message(consumer, delivery_tag, not redelivered) do
          :ok ->
            Logger.error("Rejected message #{delivery_tag}: #{inspect(reason)}")
            :ok

          {:error, reason} ->
            Logger.debug("Failed rejecting message #{delivery_tag}: #{inspect(reason)}")
        end
    end
  rescue
    exception ->
      case Consumer.reject_message(consumer, delivery_tag, not redelivered) do
        :ok ->
          Logger.error(
            "Rejected message #{delivery_tag}: #{Exception.format(:error, exception, __STACKTRACE__)}"
          )

          :ok

        {:error, reason} ->
          Logger.debug("Failed rejecting message #{delivery_tag}: #{inspect(reason)}")
      end
  end

  defp consume_ack(true = _consumer_ack, consumer, delivery_tag) do
    case Consumer.ack_message(consumer, delivery_tag) do
      :ok ->
        Logger.debug("Consumed message #{delivery_tag}, ACK sent")
        :ok

      error ->
        Logger.debug("ACK failed for message #{delivery_tag}")
        error
    end
  end

  defp consume_ack(false = _ack, _channel, delivery_tag) do
    Logger.debug(fn -> "Consumed message #{delivery_tag}, ACK not required" end)
    :ok
  end

  defp declare_exchanges(configuration, channel) do
    exchanges =
      configuration
      |> Keyword.get(:exchanges, [])
      |> Enum.map(fn {name, options} ->
        name
        |> Atom.to_string()
        |> Exchange.new(options)
      end)

    {Enum.each(exchanges, &Exchange.declare(&1, channel)), exchanges}
  end

  defp bind_exchanges(exchanges, channel), do: Enum.each(exchanges, &Exchange.bind(&1, channel))

  defp declare_queues(configuration, channel) do
    queues =
      configuration
      |> Keyword.get(:queues, [])
      |> Enum.map(fn {name, options} ->
        name
        |> Atom.to_string()
        |> Queue.new(options)
      end)

    {Enum.each(queues, &Queue.declare(&1, channel)), queues}
  end

  defp bind_queues(queues, channel), do: Enum.each(queues, &Queue.bind(&1, channel))

  defp create_producers(configuration, connection) do
    {
      :ok,
      configuration
      |> Keyword.get(:producers, [])
      |> Enum.map(&Producer.create(connection, &1))
    }
  end

  defp create_consumers(configuration, connection) do
    {
      :ok,
      configuration
      |> Keyword.get(:consumers, [])
      |> Enum.map(&Consumer.create(connection, &1))
    }
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
         {_, configuration} <-
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
          "Error creating connection #{inspect(configuration)}: missing mandatory params: #{params}"

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

  defp map_userinfo(user_info) when is_binary(user_info),
    do: String.split(user_info, ":", parts: 2)

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
      {:error, :missing_params, Enum.reject(params, &Keyword.has_key?(configuration, &1))}
    end
  end
end
