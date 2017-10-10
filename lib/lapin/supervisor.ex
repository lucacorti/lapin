defmodule Lapin.Supervisor do
  @moduledoc """
  Lapin Supervisor
  """
  use Supervisor
  require Logger

  alias Lapin.Connection

  def start_link(configuration) do
    Supervisor.start_link(__MODULE__, configuration, name: __MODULE__)
  end

  def init(configuration) do
    configuration
    |> Enum.map(fn connection ->
      with handle when not is_nil(handle) <- Keyword.get(connection, :handle),
           via <- Connection.Registry.via(handle) do
        worker(Connection, [connection, [name: via]])
      else
        nil ->
          Logger.error(fn -> "Missing :handle key for connection: #{inspect connection}" end)
        error ->
          Logger.error(fn -> error end)
      end
    end)
    |> Enum.into([supervisor(Registry, [:unique, Connection.Registry])])
    |> supervise(strategy: :one_for_one)
  end
end
