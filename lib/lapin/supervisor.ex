defmodule Lapin.Supervisor do
  @moduledoc """
  Lapin Supervisor
  """
  use Supervisor

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  end

  def init(config) do
    [
      worker(Lapin.Connection, [config])
    ]
    |> supervise(strategy: :one_for_one)
  end
end
