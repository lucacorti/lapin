defmodule Lapin.Supervisor do
  @moduledoc false

  use Supervisor
  require Logger

  @spec start_link() :: Supervisor.on_start()
  def start_link() do
    connections = Application.get_env(:lapin, :connections, [])
    Supervisor.start_link(__MODULE__, connections, name: __MODULE__)
  end

  def init(configuration) do
    configuration
    |> Enum.map(fn connection ->
      module = Keyword.get(connection, :module)
      worker(Lapin.Connection, [connection, [name: module]])
    end)
    |> supervise(strategy: :one_for_one)
  end
end
