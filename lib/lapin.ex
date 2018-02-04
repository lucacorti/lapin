defmodule Lapin do
  @moduledoc """
  Lapin, an Elixir RabbitMQ client

  Comprehensive documentation is available [here](main.html).
  """

  alias Lapin.Connection

  @typedoc """
  Lapin configuration
  """
  @type config :: [connections: [Connection.config()]]
end
