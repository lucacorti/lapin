defmodule Lapin.Producer do
  @moduledoc """
  Extensible behaviour to define pattern modules.

  Lapin provides a number of submodules which impelment the patterns found in
  the [RabbitMQ Tutorials](http://www.rabbitmq.com/getstarted.html).

  ```
  defmodule ExampleApp.SomePatter do
    use Lapin.Producer

    [... callbacks implementation ...]
  end
  ```
  """

  alias AMQP.{Basic, Channel, Confirm, Connection}
  alias Lapin.Exchange
  require Logger

  @doc """
  Request publisher confirms (RabbitMQ only)
  """
  @callback confirm(producer :: t()) :: boolean

  @doc """
  Declare exchange
  """
  @callback exchange(producer :: t()) :: Exchange.t()

  @doc """
  Request message persistence when publishing
  """
  @callback persistent(producer :: t()) :: boolean

  @doc """
  Request message mandatory routing when publishing
  """
  @callback mandatory(producer :: t()) :: boolean

  defmacro __using__([]) do
    quote do
      alias Lapin.Producer

      @behaviour Producer

      @exchange nil
      @confirm false
      @mandatory false
      @persistent false

      def confirm(%Producer{config: config}), do: Keyword.get(config, :confirm, @confirm)

      def exchange(%Producer{config: config}), do: Keyword.get(config, :exchange, @exchange)

      def mandatory(%Producer{config: config}), do: Keyword.get(config, :mandatory, @mandatory)

      def persistent(%Producer{config: config}), do: Keyword.get(config, :persistent, @persistent)

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
          channel: Channel,
          pattern: atom,
          config: config,
          exchange: String.t()
        }
  defstruct channel: nil,
            pattern: nil,
            config: nil

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
  @spec get([t], String.t()) :: t | {:error, term}
  def get(producers, exchange) do
    Enum.find(producers, &(&1.exchange == exchange))
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
