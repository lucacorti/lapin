defmodule Lapin.Queue do
  @moduledoc """
  Lapin Queue
  """

  alias AMQP.{Channel, Queue}
  require Logger

  @typedoc "Queue"
  @type t :: %__MODULE__{
          name: String.t(),
          binds: [],
          options: Keyword.t()
        }

  defstruct name: "",
            binds: [],
            options: []

  @spec new(Keyword.t()) :: %__MODULE__{}
  def new(attrs), do: struct(%__MODULE__{}, attrs)

  @spec declare(t(), Channel.t()) :: :ok | {:error, term}
  def declare(%{name: name, options: options}, channel) do
    case Queue.declare(channel, name, options) do
      {:ok, info} ->
        Logger.debug(fn -> "Declared queue #{name}: #{inspect(info)}" end)
        :ok

      error ->
        Logger.debug(fn -> "Error declaring queue #{name}: #{inspect(error)}" end)
        error
    end
  end

  def bind(%{name: name, binds: binds}, channel) do
    Enum.reduce_while(binds, :ok, fn {exchange, options}, acc ->
      case Queue.bind(channel, name, Atom.to_string(exchange), options) do
        :ok ->
          {:cont, acc}

        error ->
          {:halt, error}
      end
    end)
  end
end
