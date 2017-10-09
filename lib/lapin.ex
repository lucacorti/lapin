defmodule Lapin do
  @moduledoc """
  Lapin, an Elixir RabbitMQ client

  Comprehensive documentation is [available](main.html).
  """

  @typedoc """
  Lapin configuration
  """
  @type config :: [connections: [Lapin.Connection.config]]
end
