defmodule Lapin.Exchange do
  @moduledoc """
  Lapin Exchange
  """

  alias AMQP.{Channel, Exchange, Queue}

  require Logger

  @type name :: String.t()
  @type routing_key :: String.t()
  @type type :: :direct | :fanout | :topic

  @typedoc "Exchange"
  @type t :: %__MODULE__{
          name: name,
          binds: [],
          type: type,
          options: Keyword.t()
        }

  defstruct name: "",
            binds: [],
            type: :direct,
            options: []

  @spec new(Keyword.t()) :: %__MODULE__{}
  def new(attrs), do: struct(%__MODULE__{}, attrs)

  @spec declare(t(), Channel.t()) :: :ok | {:error, term}
  def declare(%{name: name, type: type, options: options}, channel) do
    case Exchange.declare(channel, name, type, options) do
      :ok ->
        Logger.debug(fn -> "Declared exchange #{name}: #{inspect([type, options])}" end)
        :ok

      error ->
        Logger.debug(fn -> "Error declaring exchange #{name}: #{inspect(error)}" end)
        error
    end
  end

  def bind(%{name: name, binds: binds}, channel) do
    Enum.reduce_while(binds, :ok, fn {queue, options}, acc ->
      case Queue.bind(channel, Atom.to_string(queue), name, options) do
        :ok ->
          {:cont, acc}

        error ->
          {:halt, error}
      end
    end)
  end
end
