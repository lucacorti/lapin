defmodule Lapin.Supervisor do
  @moduledoc """
  Lapin Supervisor
  """
  use Supervisor
  alias Lapin.Connection

  def start_link(configuration) do
    Supervisor.start_link(__MODULE__, configuration, name: __MODULE__)
  end

  def init(configuration) do
    configuration
    |> Enum.map(fn connection ->
      with handle when not is_nil(handle) <- Keyword.get(connection, :handle),
           via <- Connection.Registry.via(handle) do
        worker(Connection, [connection], via: via)
      else
        nil ->
          {:error, "Missing :handle key for connection: #{inspect connection}"}
        error ->
          error
      end
    end)
    |> Enum.into([supervisor(Registry, [:unique, Connection.Registry])])
    |> supervise(strategy: :one_for_one)
  end
end
