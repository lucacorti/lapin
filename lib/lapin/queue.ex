defmodule Lapin.Queue do
  @moduledoc """
  Lapin Queue
  """

  @typedoc "Queue"
  @type t :: %__MODULE__{
          name: String.t(),
          binds: [],
          declare: boolean,
          options: Keyword.t()
        }

  defstruct name: "",
            binds: [],
            declare: true,
            options: []

  alias AMQP.Queue
  require Logger

  @spec new(Keyword.t) :: %__MODULE__{}
  def new(attrs), do: struct(%__MODULE__{}, attrs)

  @spec declare(t(), Channel.t()) :: :ok | {:error, term}
  def declare(%{declare: false} = _queue, _channel), do: :ok

  def declare(%{name: name, options: options}, channel) do
    with {:ok, info} <-
           Queue.declare(
             channel,
             name,
             options
           ) do
      Logger.debug(fn -> "Declared queue #{name}: #{inspect(info)}" end)
      :ok
    else
      error ->
        error
    end
  end

  def bind(%{name: name, binds: binds}, channel) do
    binds
    |> Enum.reduce_while(:ok, fn {exchange, options}, acc ->
      case Queue.bind(channel, name, exchange, options) do
        :ok ->
          {:cont, acc}
        error ->
          {:halt, error}
      end
    end)
  end
end
