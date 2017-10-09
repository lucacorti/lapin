defmodule Lapin.Supervisor do
  use Supervisor

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  end

  def init(config) do
    {module, config} = Keyword.pop(config, :worker)
    [
      worker(module, [config])
    ]
    |> supervise(strategy: :one_for_one)
  end
end
