defmodule Lapin.Producer do
  @moduledoc """
  Extensible behaviour to define pattern modules.

  Lapin provides a number of submodules which implement the patterns found in
  the [RabbitMQ Tutorials](http://www.rabbitmq.com/getstarted.html).

  ```
  defmodule ExampleApp.SomePatter do
    use Lapin.Producer

    [... callbacks implementation ...]
  end
  ```
  """

  require Logger

  alias AMQP.{Basic, Channel, Confirm, Connection}
  alias Lapin.{Exchange, Message}

  @doc """
  Request publisher confirms (RabbitMQ only)
  """
  @callback confirm(producer :: t()) :: boolean()

  @doc """
  Declare exchange
  """
  @callback exchange(producer :: t()) :: Exchange.t()

  @doc """
  Request message persistence when publishing
  """
  @callback persistent(producer :: t()) :: boolean()

  @doc """
  Request message mandatory routing when publishing
  """
  @callback mandatory(producer :: t()) :: boolean()

  defmacro __using__([]) do
    quote do
      alias Lapin.Producer

      @behaviour Producer

      def confirm(%Producer{config: config}), do: Keyword.get(config, :confirm, false)

      def exchange(%Producer{config: config}), do: Keyword.get(config, :exchange)

      def mandatory(%Producer{config: config}), do: Keyword.get(config, :mandatory, false)

      def persistent(%Producer{config: config}), do: Keyword.get(config, :persistent, false)

      defoverridable Producer
    end
  end

  @typedoc """
  Producer configuration

  The following keys are supported:
    - pattern: producer pattern (module using the `Lapin.Producer` behaviour)

  If using the `Lapin.Pattern.Config` default implementation, the following keys are also supported:
    - exchange: declare an exchange with the broker (`Exchange.t`)
    - confirm: expect RabbitMQ publish confirms (boolean), *default: false*
    - mandatory: messages published as mandatory by default (boolean), *deafault: false*
    - persistent: messages published as persistent by default (boolean), *deafault: false*
  """
  @type config :: Keyword.t()

  @typedoc "Lapin Producer"
  @type t :: %__MODULE__{
          channel: Channel.t(),
          pattern: atom,
          config: config,
          exchange: String.t()
        }
  defstruct channel: nil,
            pattern: nil,
            config: nil,
            exchange: nil

  @doc """
  Creates a producer from configuration
  """
  @spec create(Connection.t(), config) :: t
  def create(connection, config) do
    pattern = Keyword.get(config, :pattern, Lapin.Producer.Config)
    producer = %__MODULE__{config: config, pattern: pattern}

    with {:ok, channel} <- Channel.open(connection),
         producer <- %{producer | channel: channel},
         exchange <- pattern.exchange(producer),
         :ok <- set_confirm(producer, pattern.confirm(producer)) do
      %{producer | exchange: exchange}
    else
      {:error, error} ->
        Logger.error("Error creating producer from config #{config}: #{inspect(error)}")
        producer
    end
  end

  @doc """
  Find consumer by consumer_tag
  """
  @spec get([t], String.t()) :: {:ok, t} | {:error, :not_found}
  def get(producers, exchange) do
    case Enum.find(producers, &(&1.exchange == exchange)) do
      nil -> {:error, :not_found}
      producer -> {:ok, producer}
    end
  end

  @doc """
  Publish message
  """
  @spec publish(t, Exchange.name(), Exchange.routing_key(), Message.payload(), Keyword.t()) ::
          :ok | {:error, term}
  def publish(%{channel: channel}, exchange, routing_key, payload, options) do
    Basic.publish(channel, exchange, routing_key, payload, options)
  end

  @doc """
  Wait for publish confirmation
  """
  @spec confirm(t) :: boolean()
  def confirm(%{channel: channel}) do
    case Confirm.wait_for_confirms(channel) do
      true -> true
      _ -> false
    end
  end

  defp set_confirm(_producer, false = _confirm), do: :ok

  defp set_confirm(%{channel: channel}, true = _confirm) do
    with :ok <- Confirm.select(channel),
         :ok <- Basic.return(channel, self()) do
      :ok
    else
      error ->
        error
    end
  end
end
