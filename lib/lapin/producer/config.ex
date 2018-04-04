defmodule Lapin.Producer.Config do
  @moduledoc """
  Default `Lapin.Producer` behaviour implementation for channels

  Used by default to read settings from the static configuration file and
  provide defaults for unspecified settings.
  """
  use Lapin.Producer
end
