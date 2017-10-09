defmodule Lapin.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    Application.get_env(:lapin, :connections, [])
    |> Lapin.Supervisor.start_link()
  end
end
