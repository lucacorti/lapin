defmodule Lapin.Consumer.Config do
  @moduledoc """
  Default `Lapin.Consumer` behaviour implementation for channels

  Used by default to read settings from the static configuration file and
  provide defaults for unspecified settings.
  """
  use Lapin.Consumer
end
