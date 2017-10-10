defmodule Lapin.Message do
  @moduledoc """
  Lapin Message struct
  """

  @typedoc """
  Message metadata
  """
  @type meta :: map

  @typedoc """
  Message payload
  """
  @type payload :: binary

  @typedoc """
  Lapin Message container
  """
  @type t :: %__MODULE__{meta: Message.meta, payload: Message.binary}

  defstruct [meta: nil, payload: nil]
end
