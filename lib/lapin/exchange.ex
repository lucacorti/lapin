defmodule Lapin.Exchange do
  @moduledoc """
  Lapin Exchange
  """

  @type type :: :direct | :fanout | :topic
  @typedoc "Exchange"
  @type t :: %__MODULE__{
          name: String.t(),
          type: type,
          options: Keyword.t()
        }

  alias AMQP.{Exchange, Channel}

  defstruct name: "",
            type: :direct,
            options: []

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
end
