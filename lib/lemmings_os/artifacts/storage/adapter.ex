defmodule LemmingsOs.Artifacts.Storage.Adapter do
  @moduledoc """
  Behaviour contract for trusted Artifact byte storage adapters.
  """

  @type reason :: atom() | {atom(), term()}
  @type open_result :: %{
          path: String.t(),
          filename: String.t(),
          content_type: String.t(),
          size_bytes: non_neg_integer()
        }

  @callback put(Ecto.UUID.t(), Ecto.UUID.t(), String.t(), String.t()) ::
              {:ok,
               %{
                 storage_ref: String.t(),
                 checksum: String.t(),
                 size_bytes: non_neg_integer()
               }}
              | {:error, reason()}

  @callback open(String.t(), keyword()) :: {:ok, open_result()} | {:error, reason()}
  @callback path_for(String.t(), keyword()) :: {:ok, String.t()} | {:error, reason()}
  @callback exists?(String.t(), keyword()) :: {:ok, boolean()} | {:error, reason()}
  @callback health_check(keyword()) :: :ok | {:error, reason()}
end
