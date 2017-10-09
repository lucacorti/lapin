defmodule Lapin.Worker do
  @moduledoc """
  RabbitMQ connection worker
  """
  alias Lapin.Message

  @type channel_config :: Keyword.t
  @type on_callback :: :ok | {:error, message :: String.t}

  @callback handle_cancel(channel_config) :: on_callback
  @callback handle_cancel_ok(channel_config) :: on_callback
  @callback handle_consume(channel_config, message :: Message.t) :: on_callback
  @callback handle_register(channel_config) :: on_callback
  @callback handle_publish(channel_config, message :: Message.t) :: on_callback
  @callback handle_return(channel_config, message :: Message.t) :: on_callback

  defmacro __using__(_) do
    use AMQP

    quote do
      use GenServer
      alias Lapin.Message
      require Logger

      @behaviour Lapin.Worker

      @connection_reconnect_delay 5_000
      @connection_default_params [connecion_timeout: @connection_reconnect_delay]
      @connection_mandatory_params [:host, :port, :virtual_host, :channels]
      @channel_mandatory_params [:role, :exchange, :queue]

      @spec start_link([]) :: GenServer.on_start
      def start_link(args) do
        GenServer.start_link(__MODULE__, args, name: __MODULE__)
      end

      def init(args) do
        {:ok, configuration} = cleanup_configuration(args)
        {:ok, channels} = connect(configuration)
        {:ok, %{conf: configuration, channels: channels}}
      end

      def get_channel_config(channels, consumer_tag) do
        Enum.find(channels, fn conf ->
          consumer_tag == Keyword.get(conf, :consumer_tag)
        end)
      end

      def get_channel_config(channels, exchange, routing_key) do
        Enum.find(channels, fn channel_config ->
          exchange == Keyword.get(channel_config, :exchange) && routing_key == Keyword.get(channel_config, :routing_key)
        end)
      end

      def publish(exchange, routing_key, message, options \\ []) do
        GenServer.call(__MODULE__, {:publish, exchange, routing_key, message, options})
      end

      def handle_call({:publish, exchange, routing_key, message, options}, _from, %{channels: channels} = state) do
        with channel_config when not is_nil(channel_config) <- get_channel_config(channels, exchange, routing_key),
             true <- channel_is_producer?(channel_config),
             channel when not is_nil(channel) <- Keyword.get(channel_config, :channel),
             exchange when not is_nil(exchange) <- Keyword.get(channel_config, :exchange),
             pattern <- Keyword.get(channel_config, :pattern),
             persistent <- pattern.publisher_persistent(channel_config),
             mandatory <- pattern.publisher_mandatory(channel_config),
             options <- Keyword.merge([persistent: persistent, mandatory: mandatory], options),
             :ok <- Basic.publish(channel, exchange, routing_key, message, options) do
          if not pattern.publisher_confirm(channel_config) or Confirm.wait_for_confirms(channel) do
              Logger.debug("Published to '#{exchange}'->'#{routing_key}': #{inspect message}")
              {:reply, handle_publish(channel_config, message), state}
            else
              error = "Error publishing #{inspect message} to #{exchange}: broker did not confirm reception"
              Logger.debug(error)
              {:reply, {:error, error}, state}
            end
        else
          false ->
            error = "Cannot publish, channel role is not producer"
            Logger.error(error)
            {:reply, {:error, error}, state}
          nil ->
            error = "Error publishing message: no channel for '#{exchange}'->'#{routing_key}'"
            Logger.debug(error)
            {:reply, {:error, error}, state}
          {:error, error} ->
            Logger.debug("Error sending message: #{inspect error}")
            {:reply, {:error, error}, state}
        end
      end

      def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, %{channels: channels} = state) do
        with channel_config when not is_nil(channel_config) <- get_channel_config(channels, consumer_tag),
             pattern <- Keyword.get(channel_config, :pattern),
             :ok <- handle_cancel(channel_config) do
            Logger.debug("Broker cancelled consumer_tag '#{consumer_tag}' for channel #{inspect channel_config}")
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
             pattern when not is_nil(pattern) <- Keyword.get(channel_config, :pattern),
             :ok <- handle_cancel_ok(channel_config) do
          Logger.debug("Broker confirmed cancel consumer_tag '#{consumer_tag}' for channel #{inspect channel_config}")
        else
          nil ->
            Logger.debug("Broker confirmed cancel for consumer_tag '#{consumer_tag}' for locally unknown channel")
          {:error, error} ->
            Logger.error("Error confirming cancel for consumer_tag '#{consumer_tag}': #{error}")
        end
        {:noreply, state}
      end

      def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, %{channels: channels} = state) do
        with channel_config when not is_nil(channel_config) <- get_channel_config(channels, consumer_tag),
             pattern <- Keyword.get(channel_config, :pattern),
             :ok <- handle_register(channel_config) do
            Logger.debug("Broker registered consumer_tag '#{consumer_tag}' for channel #{inspect channel_config}")
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
             pattern <- Keyword.get(channel_config, :pattern),
             :ok <- handle_return(channel_config, %Message{meta: meta, payload: payload}) do
          Logger.debug("Returned message for '#{exchange}'->'#{routing_key}': #{inspect meta}")
        else
          error ->
            Logger.debug("Error handling returned message: #{inspect error}")
        end
        {:noreply, state}
      end

      def handle_info({:DOWN, _, :process, _pid, _reason}, %{conf: conf} = state) do
        Logger.warn("Connection down, reconnecting in #{@connection_reconnect_delay} seconds...")
        :timer.sleep(@connection_reconnect_delay)
        {:ok, channels} = connect(conf)
        {:noreply, %{state | channel: channels}}
      end

      def handle_info(msg, state) do
         Logger.warn("MESSAGE: #{inspect msg}")
         {:noreply, state}
      end

      defp consume(channel_config, channel, meta, payload) do
        Logger.debug("Consuming message #{meta.delivery_tag}")
        with pattern <- Keyword.get(channel_config, :pattern),
             :ok <- handle_consume(channel_config, %Message{meta: meta, payload: payload}) do
           if not pattern.consumer_ack(channel_config) || Basic.ack(channel, meta.delivery_tag) do
             Logger.debug("Message #{meta.delivery_tag} consumed successfully, with ACK")
           else
             Logger.debug("Message #{meta.delivery_tag} consumed_successfully, without ACK")
           end
         else
          error ->
            Basic.reject(channel, meta.delivery_tag, requeue: false)
            Logger.debug("Message #{meta.delivery_tag} NOT consumed: #{inspect error}")
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
             pattern <- Keyword.get(channel_config, :pattern, Lapin.Pattern),
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
               queue_durable <-  pattern.queue_durable(channel_config),
               routing_key <- pattern.routing_key(channel_config),
               consumer_ack <- pattern.consumer_ack(channel_config),
               :ok <- Exchange.declare(channel, exchange, exchange_type, durable: exchange_durable),
               {:ok, info} <- Queue.declare(channel, queue, durable: queue_durable, arguments: queue_arguments),
               :ok <- Queue.bind(channel, queue, exchange, routing_key: routing_key) do
            channel_config = if channel_is_consumer?(channel_config) do
              with {:ok, consumer_tag} <- Basic.consume(channel, queue, nil, no_ack: not consumer_ack) do
                Logger.debug("#{consumer_tag}: consumer bound to #{exchange}->#{queue}: #{inspect info}")
                channel_config
                |> Keyword.put(:consumer_tag, consumer_tag)
              else
                error ->
                  Logger.debug("Error creating #{channel_config}: #{inspect error}")
                  {:error, error}
              end
            else
              channel_config
            end

            channel_config
            |> Keyword.merge([channel: channel, pattern: pattern, routing_key: routing_key])
          else
            error ->
              Logger.debug("Error creating #{channel_config}: #{inspect error}")
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

      defp cleanup_configuration(configuration) do
        with :ok <- check_mandatory_params(configuration, @connection_mandatory_params),
             {_, configuration} <- Keyword.get_and_update(configuration, :host, fn host ->
               {host, to_charlist(host)}
             end),
             {_, configuration} <- Keyword.get_and_update(configuration, :port, fn port ->
               {port, String.to_integer(port)}
             end),
             configuration <- map_auth_mechanisms(configuration) do
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

      defp map_auth_mechanisms(configuration) do
        {_, configuration} = configuration
        |> Keyword.get_and_update(:auth_mechanisms, fn mechanisms ->
          case mechanisms do
            list when is_list(mechanisms) ->
              {mechanisms, Enum.map(mechanisms, fn mechanism ->
                case mechanism do
                  :amqplain ->
                    &:amqp_auth_mechanisms.amqplain/3
                  :external ->
                    &:amqp_auth_mechanisms.external/3
                  :plain ->
                    &:amqp_auth_mechanisms.plain/3
                  mechanism ->
                    mechanism
                end
              end)}
            _ ->
              {mechanisms, mechanisms}
         end
       end)
       configuration
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

      defp channel_is_consumer?(channel_config) do
        role = Keyword.get(channel_config, :role, :no_role)
        role === :consumer
      end

      defp channel_is_producer?(channel_config) do
        role = Keyword.get(channel_config, :role, :no_role)
        role == :producer
      end

      def handle_cancel(_channel_config), do: :ok
      def handle_cancel_ok(_channel_config), do: :ok
      def handle_consume(_channel_config, _message), do: :ok
      def handle_publish(_channel_config, _message), do: :ok
      def handle_register(_channel_config), do: :ok
      def handle_return(_channel_config, _message), do: :ok

      defoverridable [handle_cancel: 1, handle_cancel_ok: 1, handle_consume: 2,
                      handle_publish: 2, handle_register: 1, handle_return: 2]
    end
  end
end
