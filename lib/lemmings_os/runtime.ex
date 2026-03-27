defmodule LemmingsOs.Runtime do
  @moduledoc """
  Application-level runtime entrypoints.

  This module keeps the web layer away from the persistence boundary and
  leaves room for future spawn orchestration without changing callers.
  """

  alias LemmingsOs.Lemmings.Lemming

  @doc """
  Spawns a runtime session for a lemming and first request.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> lemming =
      ...>   LemmingsOs.Factory.insert(:lemming,
      ...>     world: world,
      ...>     city: city,
      ...>     department: department,
      ...>     status: "active"
      ...>   )
      iex> {:ok, %LemmingsOs.LemmingInstances.LemmingInstance{}} =
      ...>   LemmingsOs.Runtime.spawn_session(lemming, "Summarize the roadmap")
  """
  @spec spawn_session(Lemming.t(), String.t(), keyword()) ::
          {:ok, LemmingsOs.LemmingInstances.LemmingInstance.t()}
          | {:error, Ecto.Changeset.t() | atom()}
  def spawn_session(%Lemming{} = lemming, first_request_text, opts \\ []) do
    LemmingsOs.LemmingInstances.spawn_instance(lemming, first_request_text, opts)
  end
end
