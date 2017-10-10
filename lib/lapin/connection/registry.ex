defmodule Lapin.Connection.Registry do
  @moduledoc """
  Connection process registry
  """

  @type handle :: term

  @doc """
  Returns a via tuple for `Lapin.Connection` process
  """
  @spec via(handle) :: {:via, Registry, {__MODULE__, handle}}
  def via(handle), do: {:via, Registry, {__MODULE__, handle}}
end
