defmodule Lapin.Queue do
  @moduledoc """
  Lapin Queue
  """

  @typedoc "Queue"
  @type t :: %__MODULE__{
          name: String.t(),
          declare: boolean,
          options: Keyword.t()
        }

  defstruct name: "",
            declare: true,
            options: []

  alias AMQP.Queue
  require Logger

  @spec new(Keyword.t) :: %__MODULE__{}
  def new(attrs) do
    struct(%__MODULE__{}, attrs)
  end

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
end
