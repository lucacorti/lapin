defmodule Lapin.Exchange do
  @moduledoc """
  Lapin Exchange
  """

  @type type :: :direct | :fanout | :topic
  @typedoc "Exchange"
  @type t :: %__MODULE__{
          name: String.t(),
          declare: false,
          type: type,
          options: Keyword.t(),
        }

  alias AMQP.{Exchange, Channel}

  defstruct name: "",
            declare: true,
            type: :direct,
            options: []

  @spec new(Keyword.t) :: %__MODULE__{}
  def new(attrs) do
    struct(%__MODULE__{}, attrs)
  end

  @spec declare(t(), Channel.t()) :: :ok | {:error, term}
  def declare(%{declare: false} = _exchange, _channel), do: :ok

  def declare(%{name: name, type: type, options: options}, channel) do
    Exchange.declare(
      channel,
      name,
      type,
      options
    )
  end
end
