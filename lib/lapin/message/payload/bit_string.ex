defimpl Lapin.Message.Payload, for: BitString do
  @moduledoc """
  Stub implementation of `Lapin.Message.Payload` for binaries

  Simply returns the unaltered message body for encode/decode and nil for the
  `content-type`.
  """
  def content_type(_), do: nil
  def encode(payload), do: {:ok, payload}
  def decode_into(_payload, data), do: {:ok, data}
end
