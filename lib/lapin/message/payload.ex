defprotocol Lapin.Message.Payload do
  @moduledoc """
  You can use this protocol to implement a custom message payload transformation.
  For example you could implement a JSON message with a predefined structure by
  first implementing a struct for your payload:

  ```elixir
  defmodule Example.Payload do
    defstruct [a: "a", b: "b", c: nil]
  end
  ```

  and then providing an implementation of `Lapin.Message.Payload` for it:

  ```elixir
  defimpl Lapin.Message.Payload, for: Example.Payload do
    def content_type(_payload), do: "application/json"
    def encode(payload), do: Poison.encode(payload)
    def decode_into(payload, data), do: Poison.decode(data, as: payload)
  end
  ```

  Please note you will need to add the `poison` library as a dependency on in
  your project `mix.exs` for this to work.

  Lapin will automatically encode and set the `content-type` property on publish.

  To decode messages before consuming, implement the `payload_for/2` callback
  of `Lapin.Connection` and return an instance of the payload to decode into.

  ```elixir
  defmodule Example.Connection do
    def payload_for(_channel, _message), do: %Example.Payload{}
  end
  ```

  The default implementation simply returns the unaltered binary data and sets
  the message `content-type` property to `nil`.
  """

  @typedoc "Data type implementing the `Lapin.Message.Payload` protocol"
  @type t :: term

  @typedoc "MIME content-type as defined by RFC 2045"
  @type content_type :: String.t() | nil

  @typedoc "Encode function return values"
  @type on_encode :: {:ok, binary} | {:error, term}

  @typedoc "Decode function return values"
  @type on_decode :: {:ok, t} | {:error, term}

  @doc """
  Returns the message `content-type`
  """
  @spec content_type(t) :: content_type
  def content_type(payload)

  @doc """
  Returns the encoded payload body
  """
  @spec encode(t) :: on_encode
  def encode(payload)

  @doc """
  Returns the payload with message data decoded
  """
  @spec decode_into(t, binary) :: on_decode
  def decode_into(payload, data)
end
