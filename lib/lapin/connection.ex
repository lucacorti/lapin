defmodule Lapin.Connection do
  @moduledoc """
  RabbitMQ connection handler
  """
  use AMQP
  use GenServer
  require Logger

  alias Lapin.{Message, Worker}

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
  Channel role
  """
  @type role :: :consumer | :producer

  @typedoc """
  Connection configuration

  The following keys are supported:
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
    - role: channel role (:consumer | :producer)
    - worker: channel worker (module impelmenting the `Lapin.Worker` behaviour)
    - exchange: broker exchange (string)
    - queue: broker queue (string)

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

  @connection_reconnect_delay 5_000
  @connection_default_params [connecion_timeout: @connection_reconnect_delay]
  @connection_mandatory_params [:handle]
  @channel_mandatory_params [:role, :worker, :exchange, :queue]

  @doc """
  Starts a `Lapin.Connection` with the specified configuration
  """
  @spec start_link(config, options :: GenServer.options) :: GenServer.on_start
  def start_link(configuration, options \\ []) do
    {:ok, configuration} = cleanup_configuration(configuration)
    GenServer.start_link(__MODULE__, configuration, options)
  end

  def init(configuration) do
    {:ok, channels} = connect(configuration)
    {:ok, %{configuration: configuration, channels: channels}}
  end

  @doc """
  Publishes a message to the specified exchange with the given routing_key
  """
  @spec publish(server :: GenServer.server, exchange, routing_key,
  message :: Message.t, options :: Keyword.t) :: Worker.on_callback
  def publish(server, exchange, routing_key, message, options \\ []) do
    GenServer.call(server, {:publish, exchange, routing_key, message, options})
  end

  def handle_call({:publish, exchange, routing_key, message, options}, _from, %{channels: channels} = state) do
    with channel_config when not is_nil(channel_config) <- get_channel_config(channels, exchange, routing_key),
         true <- channel_is_producer?(channel_config),
         channel when not is_nil(channel) <- Keyword.get(channel_config, :channel),
         worker <- Keyword.get(channel_config, :worker),
         pattern <- worker.pattern(),
         persistent <- pattern.publisher_persistent(channel_config),
         mandatory <- pattern.publisher_mandatory(channel_config),
         options <- Keyword.merge([persistent: persistent, mandatory: mandatory], options),
         :ok <- Basic.publish(channel, exchange, routing_key, message.payload, options) do
      if not pattern.publisher_confirm(channel_config) or Confirm.wait_for_confirms(channel) do
          Logger.debug(fn -> "Published to '#{exchange}'->'#{routing_key}': #{inspect message}" end)
          {:reply, worker.handle_publish(channel_config, message), state}
        else
          error = "Error publishing #{inspect message} to #{exchange}: broker did not confirm reception"
          Logger.debug(fn -> error end)
          {:reply, {:error, error}, state}
        end
    else
      false ->
        error = "Cannot publish, channel role is not producer"
        Logger.error(error)
        {:reply, {:error, error}, state}
      nil ->
        error = "Error publishing message: no channel for '#{exchange}'->'#{routing_key}'"
        Logger.debug(fn -> error end)
        {:reply, {:error, error}, state}
      {:error, error} ->
        Logger.debug(fn -> "Error sending message: #{inspect error}" end)
        {:reply, {:error, error}, state}
    end
  end

  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, %{channels: channels} = state) do
    with channel_config when not is_nil(channel_config) <- get_channel_config(channels, consumer_tag),
         worker <- Keyword.get(channel_config, :worker),
         :ok <- worker.handle_cancel(channel_config) do
        Logger.debug(fn -> "Broker cancelled consumer_tag '#{consumer_tag}' for channel #{inspect channel_config}" end)
    else
      nil ->
        Logger.warn("Broker cancelled consumer_tag '#{consumer_tag}' for locally unknown channel")
      {:error, error} ->
        Logger.error("Error canceling consumer_tag '#{consumer_tag}': #{error}")
    end
    {:stop, :normal, state}
  end

  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, %{channels: channels} = state) do
    with channel_config when not is_nil(channel_config) <- get_channel_config(channels, consumer_tag),
         worker <- Keyword.get(channel_config, :worker),
         :ok <- worker.handle_cancel_ok(channel_config) do
      Logger.debug(fn -> "Broker confirmed cancel consumer_tag '#{consumer_tag}' for channel #{inspect channel_config}" end)
    else
      nil ->
        Logger.debug(fn -> "Broker confirmed cancel for consumer_tag '#{consumer_tag}' for locally unknown channel" end)
      {:error, error} ->
        Logger.error("Error confirming cancel for consumer_tag '#{consumer_tag}': #{error}")
    end
    {:noreply, state}
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, %{channels: channels} = state) do
    with channel_config when not is_nil(channel_config) <- get_channel_config(channels, consumer_tag),
         worker <- Keyword.get(channel_config, :worker),
         :ok <- worker.handle_consume_ok(channel_config) do
        Logger.debug(fn -> "Broker registered consumer_tag '#{consumer_tag}' for channel #{inspect channel_config}" end)
    else
      nil ->
        Logger.warn("Broker registered consumer_tag '#{consumer_tag}', unknown channel")
      {:error, error} ->
        Logger.error("Broker error registration callback: #{error}")
    end
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, meta}, %{channels: channels} = state) do
    with channel_config when not is_nil(channel_config) <- get_channel_config(channels, meta.consumer_tag),
         channel when not is_nil(channel) <- Keyword.get(channel_config, :channel) do
      spawn fn ->
        consume(channel_config, channel, meta, payload)
      end
    else
      nil ->
        Logger.error("Error processing message #{meta.delivery_tag}, unknown channel")
    end
    {:noreply, state}
  end

  def handle_info({:basic_return, payload, %{exchange: exchange, routing_key: routing_key} = meta}, %{channels: channels} = state) do
    with channel_config when not is_nil(channel_config) <- get_channel_config(channels, exchange, routing_key),
         worker <- Keyword.get(channel_config, :worker),
         :ok <- worker.handle_return(channel_config, %Message{meta: meta, payload: payload}) do
      Logger.debug(fn -> "Returned message for '#{exchange}'->'#{routing_key}': #{inspect meta}" end)
    else
      error ->
        Logger.debug(fn -> "Error handling returned message: #{inspect error}" end)
    end
    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, _pid, _reason}, %{configuration: configuration} = state) do
    Logger.warn("Connection down, reconnecting in #{@connection_reconnect_delay} seconds...")
    :timer.sleep(@connection_reconnect_delay)
    {:ok, channels} = connect(configuration)
    {:noreply, %{state | channel: channels}}
  end

  def handle_info(msg, state) do
     Logger.warn("MESSAGE: #{inspect msg}")
     {:noreply, state}
  end

  defp consume(channel_config, channel, meta, payload) do
    Logger.debug(fn -> "Consuming message #{meta.delivery_tag}" end)
    with worker <- Keyword.get(channel_config, :worker),
         pattern <- worker.pattern(),
         :ok <- worker.handle_deliver(channel_config, %Message{meta: meta, payload: payload}) do
       if not pattern.consumer_ack(channel_config) || Basic.ack(channel, meta.delivery_tag) do
         Logger.debug(fn -> "Message #{meta.delivery_tag} consumed successfully, with ACK" end)
       else
         Logger.debug(fn -> "Message #{meta.delivery_tag} consumed_successfully, without ACK" end)
       end
     else
      error ->
        Basic.reject(channel, meta.delivery_tag, requeue: false)
        Logger.debug(fn -> "Message #{meta.delivery_tag} NOT consumed: #{inspect error}" end)
    end

    rescue
      _exception ->
        Basic.reject(channel, meta.delivery_tag, requeue: not meta.redelivered)
        Logger.error("Crash processing message #{meta.delivery_tag}, rejected")
  end

  defp connect(configuration) do
    with {channels, configuration} <- Keyword.pop(configuration, :channels, []),
         configuration <- Keyword.merge(@connection_default_params, configuration),
         {:ok, connection} <- Connection.open(configuration) do
      Process.monitor(connection.pid)
      {:ok, Enum.map(channels, &create_channel(connection, &1))}
    else
      {:error, _} ->
        :timer.sleep(@connection_reconnect_delay)
        connect(configuration)
    end
  end

  defp create_channel(connection, channel_config) do
    with :ok <- check_mandatory_params(channel_config, @channel_mandatory_params),
         role when not is_nil(role) <- Keyword.get(channel_config, :role),
         exchange when not is_nil(exchange) <- Keyword.get(channel_config, :exchange),
         queue when not is_nil(queue) <- Keyword.get(channel_config, :queue),
         worker <- Keyword.get(channel_config, :worker),
         pattern <- worker.pattern(),
         {:ok, channel} <- Channel.open(connection),
         channel_config <- Keyword.put(channel_config, :channel, channel),
         prefetch <- pattern.consumer_prefetch(channel_config),
         confirm <- pattern.publisher_confirm(channel_config) do
      if channel_is_consumer?(channel_config) && prefetch do
        :ok = Basic.qos(channel, prefetch_count: prefetch)
      end

      if channel_is_producer?(channel_config) && confirm do
        :ok = Confirm.select(channel)
        :ok = Basic.return(channel, self())
      end

      with exchange_type <- pattern.exchange_type(channel_config),
           exchange_durable <- pattern.exchange_durable(channel_config),
           queue_arguments <- pattern.queue_arguments(channel_config),
           queue_durable <- pattern.queue_durable(channel_config),
           routing_key <- pattern.routing_key(channel_config),
           consumer_ack <- pattern.consumer_ack(channel_config),
           :ok <- Exchange.declare(channel, exchange, exchange_type, durable: exchange_durable),
           {:ok, info} <- Queue.declare(channel, queue, durable: queue_durable, arguments: queue_arguments),
           :ok <- Queue.bind(channel, queue, exchange, routing_key: routing_key) do
        channel_config = if channel_is_consumer?(channel_config) do
          with {:ok, consumer_tag} <- Basic.consume(channel, queue, nil, no_ack: not consumer_ack) do
            Logger.debug(fn -> "#{consumer_tag}: consumer bound to #{exchange}->#{queue}: #{inspect info}" end)
            channel_config
            |> Keyword.put(:consumer_tag, consumer_tag)
          else
            error ->
              Logger.debug(fn -> "Error creating #{channel_config}: #{inspect error}" end)
              {:error, error}
          end
        else
          channel_config
        end

        channel_config
        |> Keyword.merge([channel: channel, worker: worker, routing_key: routing_key])
      else
        error ->
          Logger.debug(fn -> "Error creating #{channel_config}: #{inspect error}" end)
          {:error, error}
      end
    else
      {:error, :missing_params, missing_params} ->
        missing_params = missing_params
        |> Enum.map(&Atom.to_string(&1))
        |> Enum.join(", ")
        error = "Error creating channel #{inspect channel_config}: missing mandatory params: #{missing_params}"
        Logger.error(error)
        {:error, error}
      {:error, error} ->
        Logger.error("Error creating channel #{channel_config}: #{inspect error}")
        {:error, error}
    end
  end

  defp get_channel_config(channels, consumer_tag) do
    Enum.find(channels, fn conf ->
      consumer_tag == Keyword.get(conf, :consumer_tag)
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
         {_, configuration} = Keyword.get_and_update(configuration, :auth_mechanisms, fn mechanisms ->
           case mechanisms do
             list when is_list(list) ->
               {mechanisms, Enum.map(list, &map_auth_mechanism(&1))}
             _ ->
               :pop
          end
        end) do
      {:ok, configuration}
    else
      {:error, :missing_params, missing_params} ->
        missing_params = missing_params
        |> Enum.map(&Atom.to_string(&1))
        |> Enum.join(", ")
        error = "Error creating connection #{inspect configuration}: missing mandatory params: #{missing_params}"
        Logger.error(error)
        {:error, error}
    end
  end

  defp map_auth_mechanism(:amqplain), do: &:amqp_auth_mechanisms.amqplain/3
  defp map_auth_mechanism(:external), do: &:amqp_auth_mechanisms.external/3
  defp map_auth_mechanism(:plain), do: &:amqp_auth_mechanisms.plain/3
  defp map_auth_mechanism(auth_mechanism), do: auth_mechanism

  defp map_host(nil), do: 'localhost'
  defp map_host(host) when is_binary(host), do: String.to_charlist(host)
  defp map_host(host), do: host

  defp map_port(nil), do: 5672
  defp map_port(port) when is_binary(port), do: String.to_integer(port)
  defp map_port(port), do: port

  defp check_mandatory_params(configuration, params) do
    if Enum.all?(params, &Keyword.has_key?(configuration, &1)) do
      :ok
    else
      missing_params = params
      |> Enum.reject(&Keyword.has_key?(configuration, &1))
      {:error, :missing_params, missing_params}
    end
  end

  defp channel_is_consumer?(channel_config) do
    Keyword.get(channel_config, :role, :no_role) === :consumer
  end

  defp channel_is_producer?(channel_config) do
    Keyword.get(channel_config, :role, :no_role) === :producer
  end
end
