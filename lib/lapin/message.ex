defmodule Lapin.Message do
  @moduledoc """
  AMQP Message Structure
  """

  @type meta :: map
  @type payload :: binary
  @type t :: %__MODULE__{meta: Message.meta, payload: Message.binary}

  defstruct [meta: nil, payload: nil]
end
