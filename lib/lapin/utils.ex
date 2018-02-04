defmodule Lapin.Utils do
  @moduledoc """
  Misc utility functions
  """

  @doc """
  Checks the cconfiguration contains some keys
  """
  @spec check_mandatory_params(Keyword.t(), [atom]) :: :ok | {:error, :missing_params, [atom]}
  def check_mandatory_params(configuration, params) do
    if Enum.all?(params, &Keyword.has_key?(configuration, &1)) do
      :ok
    else
      missing_params = Enum.reject(params, &Keyword.has_key?(configuration, &1))
      {:error, :missing_params, missing_params}
    end
  end
end
