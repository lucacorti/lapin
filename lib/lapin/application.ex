defmodule Lapin.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    :lapin
    |> Application.get_env(:connections, [])
    |> Lapin.Connection.Supervisor.start_link()
  end
end
