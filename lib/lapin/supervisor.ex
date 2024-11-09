defmodule Lapin.Supervisor do
  @moduledoc "Lapin Supervisor"

  use Supervisor

  require Logger

  @spec start_link :: Supervisor.on_start()
  def start_link do
    connections = Application.get_env(:lapin, :connections, [])
    Supervisor.start_link(__MODULE__, connections, name: __MODULE__)
  end

  def init(configuration) do
    configuration
    |> Enum.map(fn connection ->
      module = Keyword.get(connection, :module)
      %{id: module, start: {Lapin.Connection, :start_link, [connection, [name: module]]}}
    end)
    |> Supervisor.init(strategy: :one_for_one)
  end

  def child_spec(_args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }
  end
end
