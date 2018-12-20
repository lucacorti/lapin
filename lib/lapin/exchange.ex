defmodule Lapin.Exchange do
  @moduledoc """
  Lapin Exchange
  """

  alias AMQP.{Channel, Exchange, Queue}

  @type type :: :direct | :fanout | :topic
  @typedoc "Exchange"
  @type t :: %__MODULE__{
          name: String.t(),
          binds: [],
          declare: false,
          type: type,
          options: Keyword.t()
        }

  defstruct name: "",
            binds: [],
            declare: true,
            type: :direct,
            options: []

  @spec new(Keyword.t()) :: %__MODULE__{}
  def new(attrs), do: struct(%__MODULE__{}, attrs)

  @spec declare(t(), Channel.t()) :: :ok | {:error, term}
  def declare(nil = _exchange, _channel), do: :ok

  def declare(%{name: name, type: type, options: options}, channel) do
    Exchange.declare(
      channel,
      name,
      type,
      options
    )
  end

  def bind(%{name: name, binds: binds}, channel) do
    binds
    |> Enum.reduce_while(:ok, fn {queue, options}, acc ->
      case Queue.bind(channel, queue, name, options) do
        :ok ->
          {:cont, acc}

        error ->
          {:halt, error}
      end
    end)
  end
end
