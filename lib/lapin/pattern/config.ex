defmodule Lapin.Pattern.Config do
  @moduledoc """
  Default `Lapin.Pattern` behaviour implementation for workers

  Used by default to read settings from the static configuration file and
  provide defaults for unspecified settings.
  """
  use Lapin.Pattern
end
